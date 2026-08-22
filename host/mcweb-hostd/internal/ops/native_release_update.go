package ops

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/mcweb/mcweb-hostd/internal/config"
)

const (
	defaultReleaseArchiveLimit   int64 = 4 << 30
	defaultReleaseExtractLimit   int64 = 16 << 30
	defaultReleaseEntryLimit           = 200_000
	defaultChecksumDownloadLimit int64 = 4 << 10
)

var (
	releaseVersionPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)
	unixUserPattern       = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]{0,63}$`)
	nativeUpdateMu        sync.Mutex
)

type nativeReleaseUpdater struct {
	cfg          *config.Config
	client       *http.Client
	runCommand   func(*exec.Cmd) ([]byte, error)
	prepareOwner func(string, string) error
	archiveLimit int64
	extractLimit int64
	entryLimit   int
}

func newNativeReleaseUpdater(cfg *config.Config) *nativeReleaseUpdater {
	return &nativeReleaseUpdater{
		cfg:    cfg,
		client: secureReleaseHTTPClient(),
		runCommand: func(cmd *exec.Cmd) ([]byte, error) {
			return cmd.CombinedOutput()
		},
		prepareOwner: prepareReleaseOwnership,
		archiveLimit: defaultReleaseArchiveLimit,
		extractLimit: defaultReleaseExtractLimit,
		entryLimit:   defaultReleaseEntryLimit,
	}
}

func secureReleaseHTTPClient() *http.Client {
	return &http.Client{
		Timeout: 30 * time.Minute,
		CheckRedirect: func(request *http.Request, via []*http.Request) error {
			if len(via) >= 10 {
				return errors.New("too many release download redirects")
			}
			if request.URL.User != nil {
				return errors.New("release download redirect contains credentials")
			}
			if request.URL.Scheme != "https" && !(request.URL.Scheme == "http" && isLoopbackHost(request.URL.Hostname())) {
				return errors.New("release download redirect must use HTTPS")
			}
			return nil
		},
	}
}

func (u *nativeReleaseUpdater) Run(job *Job, version string) error {
	nativeUpdateMu.Lock()
	defer nativeUpdateMu.Unlock()

	if err := validateReleaseVersion(version); err != nil {
		return err
	}
	if u.cfg == nil {
		return errors.New("native update configuration is unavailable")
	}
	if u.client == nil || u.runCommand == nil || u.prepareOwner == nil {
		return errors.New("native update dependencies are unavailable")
	}
	if !unixUserPattern.MatchString(u.cfg.McwebUser) {
		return errors.New("mcweb_user must be a simple Unix account name")
	}

	currentLink, appBase, releasesRoot, candidate, err := nativeReleasePaths(u.cfg.McwebRoot, version)
	if err != nil {
		return err
	}
	currentBefore, err := currentReleaseTarget(currentLink)
	if err != nil {
		return err
	}
	if _, err := os.Lstat(candidate); err == nil {
		return fmt.Errorf("candidate release already exists; inspect it or choose a new version: %s", candidate)
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("inspect candidate release path: %w", err)
	}
	if err := os.MkdirAll(releasesRoot, 0o755); err != nil {
		return fmt.Errorf("create releases directory: %w", err)
	}

	archiveURL, checksumURL, err := releaseAssetURLs(u.cfg.ReleaseURL, version)
	if err != nil {
		return err
	}
	workspace, err := os.MkdirTemp(releasesRoot, ".hostd-update-"+version+"-")
	if err != nil {
		return fmt.Errorf("create release staging directory: %w", err)
	}
	defer os.RemoveAll(workspace)

	archivePath := filepath.Join(workspace, "release.tar.gz")
	checksumPath := filepath.Join(workspace, "release.tar.gz.sha256")
	job.Append("Downloading checksum for release " + version)
	if err := downloadFile(u.client, checksumURL, checksumPath, defaultChecksumDownloadLimit); err != nil {
		return fmt.Errorf("download release checksum: %w", err)
	}
	job.Append("Downloading release archive " + version)
	if err := downloadFile(u.client, archiveURL, archivePath, u.archiveLimit); err != nil {
		return fmt.Errorf("download release archive: %w", err)
	}
	if err := verifyReleaseChecksum(archivePath, checksumPath); err != nil {
		return err
	}
	job.Append("Release checksum verified")

	unpackRoot := filepath.Join(workspace, "unpacked")
	if err := os.Mkdir(unpackRoot, 0o700); err != nil {
		return fmt.Errorf("create unpack directory: %w", err)
	}
	expectedRoot := "mcweb-" + version
	if err := extractReleaseArchive(archivePath, unpackRoot, expectedRoot, u.extractLimit, u.entryLimit); err != nil {
		return err
	}
	stagedCandidate := filepath.Join(unpackRoot, expectedRoot)
	if err := validateStagedRelease(stagedCandidate, version); err != nil {
		return err
	}
	if err := u.prepareOwner(stagedCandidate, u.cfg.McwebUser); err != nil {
		return fmt.Errorf("prepare candidate ownership: %w", err)
	}

	// All hostd instances in this process are serialized above. Refuse an
	// existing target immediately before the same-filesystem atomic publish so
	// normal concurrent web/CLI requests cannot replace a candidate.
	if _, err := os.Lstat(candidate); err == nil {
		return fmt.Errorf("candidate release appeared during staging; refusing to overwrite: %s", candidate)
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("recheck candidate release path: %w", err)
	}
	if err := os.Rename(stagedCandidate, candidate); err != nil {
		return fmt.Errorf("publish candidate release without changing current: %w", err)
	}
	job.Append("Candidate release staged at " + candidate)

	updateBin := filepath.Join(candidate, "bin", "update")
	confirmation := "UPDATE:" + version
	cmd := exec.Command(updateBin, "--release", candidate, "--confirm", confirmation)
	cmd.Dir = candidate
	cmd.Env = append(os.Environ(),
		"MCWEB_APP_BASE="+appBase,
		"MCWEB_RELEASES_DIR="+releasesRoot,
		"MCWEB_CURRENT_LINK="+currentLink,
		"MCWEB_CONFIG_FILE="+u.cfg.McwebEnvFile,
		"MCWEB_APP_USER="+u.cfg.McwebUser,
		"MCWEB_READY_URL="+strings.TrimRight(u.cfg.HealthURL, "/")+"/health/ready",
	)
	job.Append("Running candidate update contract for " + version)
	out, commandErr := u.runCommand(cmd)
	if text := strings.TrimSpace(string(out)); text != "" {
		job.Append(text)
	}
	if commandErr == nil {
		return nil
	}

	currentAfter, currentErr := currentReleaseTarget(currentLink)
	if currentErr != nil {
		return fmt.Errorf("candidate update failed and current release cannot be verified; immediate operator intervention is required: %w", commandErr)
	}
	if currentAfter != currentBefore {
		return fmt.Errorf("candidate update failed and current release changed from %s to %s; immediate operator intervention is required: %w", filepath.Base(currentBefore), filepath.Base(currentAfter), commandErr)
	}
	return fmt.Errorf("candidate update failed; current release remains %s and the staged candidate was retained for inspection: %w", filepath.Base(currentBefore), commandErr)
}

func validateReleaseVersion(version string) error {
	if version == "" {
		return errors.New("native update requires an explicit release version")
	}
	if len(version) > 128 || !releaseVersionPattern.MatchString(version) || version == "." || version == ".." {
		return errors.New("release version may contain only ASCII letters, digits, dots, underscores, and hyphens, and must begin with a letter or digit")
	}
	return nil
}

func nativeReleasePaths(configuredRoot, version string) (currentLink, appBase, releasesRoot, candidate string, err error) {
	if configuredRoot == "" {
		configuredRoot = "/opt/mcweb/current"
	}
	currentLink = filepath.Clean(configuredRoot)
	if !filepath.IsAbs(currentLink) {
		err = errors.New("mcweb_root must be an absolute current-release symlink")
		return
	}
	appBase = filepath.Dir(currentLink)
	releasesRoot = filepath.Join(appBase, "releases")
	candidate = filepath.Join(releasesRoot, version)
	if filepath.Dir(candidate) != releasesRoot {
		err = errors.New("candidate release must be a direct child of the releases directory")
	}
	return
}

func currentReleaseTarget(currentLink string) (string, error) {
	info, err := os.Lstat(currentLink)
	if err != nil {
		return "", fmt.Errorf("inspect current release pointer: %w", err)
	}
	if info.Mode()&os.ModeSymlink == 0 {
		return "", errors.New("mcweb_root must point to the current release symbolic link")
	}
	target, err := filepath.EvalSymlinks(currentLink)
	if err != nil {
		return "", fmt.Errorf("resolve current release pointer: %w", err)
	}
	target, err = filepath.Abs(target)
	if err != nil {
		return "", fmt.Errorf("canonicalize current release target: %w", err)
	}
	return filepath.Clean(target), nil
}

func releaseAssetURLs(base, version string) (string, string, error) {
	parsed, err := url.Parse(strings.TrimSpace(base))
	if err != nil || parsed.Host == "" {
		return "", "", errors.New("release_url must be an absolute HTTPS URL")
	}
	if parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
		return "", "", errors.New("release_url must not contain credentials, query parameters, or a fragment")
	}
	if parsed.Scheme != "https" && !(parsed.Scheme == "http" && isLoopbackHost(parsed.Hostname())) {
		return "", "", errors.New("release_url must use HTTPS; HTTP is allowed only for loopback testing")
	}
	asset := "mcweb-" + version + ".tar.gz"
	archiveURL, err := url.JoinPath(parsed.String(), version, asset)
	if err != nil {
		return "", "", fmt.Errorf("build release archive URL: %w", err)
	}
	return archiveURL, archiveURL + ".sha256", nil
}

func isLoopbackHost(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func downloadFile(client *http.Client, sourceURL, destination string, limit int64) (err error) {
	request, err := http.NewRequest(http.MethodGet, sourceURL, nil)
	if err != nil {
		return err
	}
	response, err := client.Do(request)
	if err != nil {
		var requestErr *url.Error
		if errors.As(err, &requestErr) {
			return fmt.Errorf("release download request failed: %w", requestErr.Err)
		}
		return errors.New("release download request failed")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("release server returned HTTP %d", response.StatusCode)
	}
	if response.ContentLength > limit {
		return fmt.Errorf("download exceeds the %d-byte limit", limit)
	}

	file, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	defer func() {
		if closeErr := file.Close(); err == nil {
			err = closeErr
		}
		if err != nil {
			_ = os.Remove(destination)
		}
	}()
	written, err := io.Copy(file, io.LimitReader(response.Body, limit+1))
	if err != nil {
		return err
	}
	if written > limit {
		return fmt.Errorf("download exceeds the %d-byte limit", limit)
	}
	return file.Sync()
}

func verifyReleaseChecksum(archivePath, checksumPath string) error {
	checksumData, err := os.ReadFile(checksumPath)
	if err != nil {
		return fmt.Errorf("read release checksum: %w", err)
	}
	fields := strings.Fields(string(checksumData))
	if len(fields) == 0 || len(fields[0]) != sha256.Size*2 {
		return errors.New("release checksum file does not contain a SHA-256 digest")
	}
	expected, err := hex.DecodeString(fields[0])
	if err != nil || len(expected) != sha256.Size {
		return errors.New("release checksum file does not contain a valid SHA-256 digest")
	}
	archive, err := os.Open(archivePath)
	if err != nil {
		return fmt.Errorf("open release archive for verification: %w", err)
	}
	defer archive.Close()
	hasher := sha256.New()
	if _, err := io.Copy(hasher, archive); err != nil {
		return fmt.Errorf("hash release archive: %w", err)
	}
	if subtle.ConstantTimeCompare(expected, hasher.Sum(nil)) != 1 {
		return errors.New("release archive SHA-256 does not match the published checksum")
	}
	return nil
}

func extractReleaseArchive(archivePath, destination, expectedRoot string, byteLimit int64, entryLimit int) error {
	archive, err := os.Open(archivePath)
	if err != nil {
		return fmt.Errorf("open verified release archive: %w", err)
	}
	defer archive.Close()
	gzipReader, err := gzip.NewReader(archive)
	if err != nil {
		return fmt.Errorf("open release gzip stream: %w", err)
	}
	defer gzipReader.Close()

	tarReader := tar.NewReader(gzipReader)
	seen := make(map[string]struct{})
	var total int64
	entries := 0
	for {
		header, err := tarReader.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return fmt.Errorf("read release archive: %w", err)
		}
		entries++
		if entries > entryLimit {
			return fmt.Errorf("release archive exceeds the %d-entry limit", entryLimit)
		}
		cleanName, err := safeArchivePath(header.Name, expectedRoot)
		if err != nil {
			return err
		}
		if _, duplicate := seen[cleanName]; duplicate {
			return fmt.Errorf("release archive contains a duplicate entry: %s", cleanName)
		}
		seen[cleanName] = struct{}{}

		target := filepath.Join(destination, filepath.FromSlash(cleanName))
		mode := header.FileInfo().Mode().Perm()
		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, normalizedMode(mode, true)); err != nil {
				return fmt.Errorf("create release directory: %w", err)
			}
			if err := os.Chmod(target, normalizedMode(mode, true)); err != nil {
				return fmt.Errorf("set release directory permissions: %w", err)
			}
		case tar.TypeReg, tar.TypeRegA:
			if header.Size < 0 || header.Size > byteLimit-total {
				return fmt.Errorf("release archive exceeds the %d-byte extraction limit", byteLimit)
			}
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return fmt.Errorf("create release parent directory: %w", err)
			}
			file, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, normalizedMode(mode, false))
			if err != nil {
				return fmt.Errorf("create release file: %w", err)
			}
			written, copyErr := io.CopyN(file, tarReader, header.Size)
			closeErr := file.Close()
			if copyErr != nil {
				return fmt.Errorf("extract release file: %w", copyErr)
			}
			if closeErr != nil {
				return fmt.Errorf("close release file: %w", closeErr)
			}
			total += written
		default:
			return fmt.Errorf("release archive contains unsupported entry type %d at %s", header.Typeflag, cleanName)
		}
	}
	if entries == 0 {
		return errors.New("release archive is empty")
	}
	return nil
}

func safeArchivePath(name, expectedRoot string) (string, error) {
	if name == "" || strings.Contains(name, `\`) || path.IsAbs(name) {
		return "", fmt.Errorf("release archive contains an unsafe path: %q", name)
	}
	cleanName := path.Clean(name)
	if cleanName == "." || cleanName == ".." || strings.HasPrefix(cleanName, "../") {
		return "", fmt.Errorf("release archive contains an unsafe path: %q", name)
	}
	if cleanName != expectedRoot && !strings.HasPrefix(cleanName, expectedRoot+"/") {
		return "", fmt.Errorf("release archive entry is outside the expected %s root: %q", expectedRoot, name)
	}
	return cleanName, nil
}

func normalizedMode(mode os.FileMode, directory bool) os.FileMode {
	mode &= 0o777
	if mode != 0 {
		return mode
	}
	if directory {
		return 0o755
	}
	return 0o644
}

func validateStagedRelease(candidate, version string) error {
	versionData, err := os.ReadFile(filepath.Join(candidate, "VERSION"))
	if err != nil {
		return fmt.Errorf("candidate VERSION is missing: %w", err)
	}
	if strings.TrimSpace(string(versionData)) != version {
		return errors.New("candidate VERSION does not match the requested release")
	}
	for _, relative := range []string{"Gemfile.lock", filepath.Join("bin", "rails"), filepath.Join("bin", "rollback"), filepath.Join("bin", "update")} {
		info, err := os.Lstat(filepath.Join(candidate, relative))
		if err != nil {
			return fmt.Errorf("candidate is missing %s", relative)
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("candidate %s must be a regular file", relative)
		}
		if strings.HasPrefix(relative, "bin"+string(filepath.Separator)) && runtime.GOOS != "windows" && info.Mode().Perm()&0o111 == 0 {
			return fmt.Errorf("candidate %s is not executable", relative)
		}
	}
	assets, err := os.Lstat(filepath.Join(candidate, "public", "assets"))
	if err != nil || !assets.IsDir() {
		return errors.New("candidate precompiled public/assets directory is missing")
	}
	return nil
}

func prepareReleaseOwnership(candidate, account string) error {
	cmd := exec.Command("chown", "-R", "--", account+":"+account, candidate)
	out, err := cmd.CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(out))
		if message == "" {
			return err
		}
		return fmt.Errorf("%w: %s", err, message)
	}
	return nil
}
