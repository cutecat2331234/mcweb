package ops

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/mcweb/mcweb-hostd/internal/config"
)

type testArchiveEntry struct {
	name     string
	body     []byte
	mode     int64
	typeflag byte
	linkname string
}

func TestNativeReleaseUpdateStagesVerifiedCandidateAndCallsExactContract(t *testing.T) {
	const version = "v2026.08.22"
	archive := buildReleaseArchive(t, version, nil)
	server := releaseServer(t, version, archive, checksumFor(archive))
	defer server.Close()

	cfg, currentTarget, candidate := testNativeReleaseConfig(t, server.URL, version)
	updater := newNativeReleaseUpdater(cfg)
	updater.client = server.Client()
	updater.prepareOwner = func(stagedPath, account string) error {
		if filepath.Base(stagedPath) != "mcweb-"+version || account != "mcweb" {
			t.Fatalf("unexpected ownership preparation: path=%q account=%q", stagedPath, account)
		}
		return nil
	}
	var commandName string
	var commandArgs []string
	var commandEnv []string
	updater.runCommand = func(cmd *exec.Cmd) ([]byte, error) {
		commandName = cmd.Path
		commandArgs = append([]string(nil), cmd.Args[1:]...)
		commandEnv = append([]string(nil), cmd.Env...)
		return []byte("Update complete and ready"), nil
	}

	job := &Job{}
	if err := updater.Run(job, version); err != nil {
		t.Fatalf("Run returned error: %v", err)
	}
	if commandName != filepath.Join(candidate, "bin", "update") {
		t.Fatalf("command path = %q, want candidate updater", commandName)
	}
	wantArgs := []string{"--release", candidate, "--confirm", "UPDATE:" + version}
	if !reflect.DeepEqual(commandArgs, wantArgs) {
		t.Fatalf("command args = %#v, want %#v", commandArgs, wantArgs)
	}
	assertEnvironmentEntry(t, commandEnv, "MCWEB_RELEASES_DIR="+filepath.Dir(candidate))
	assertEnvironmentEntry(t, commandEnv, "MCWEB_CURRENT_LINK="+cfg.McwebRoot)
	assertEnvironmentEntry(t, commandEnv, "MCWEB_CONFIG_FILE="+cfg.McwebEnvFile)
	assertEnvironmentEntry(t, commandEnv, "MCWEB_APP_USER=mcweb")
	assertEnvironmentEntry(t, commandEnv, "MCWEB_READY_URL=http://127.0.0.1:3999/health/ready")
	if got := mustCurrentTarget(t, cfg.McwebRoot); got != currentTarget {
		t.Fatalf("current target changed from %q to %q", currentTarget, got)
	}
	if data, err := os.ReadFile(filepath.Join(candidate, "VERSION")); err != nil || strings.TrimSpace(string(data)) != version {
		t.Fatalf("published candidate VERSION = %q, err=%v", data, err)
	}
	if strings.Contains(job.LogText(), server.URL) {
		t.Fatal("job log exposed the configured release URL")
	}
}

func TestNativeReleaseUpdateChecksumMismatchFailsBeforePublish(t *testing.T) {
	const version = "v2"
	archive := buildReleaseArchive(t, version, nil)
	server := releaseServer(t, version, archive, strings.Repeat("0", 64)+"  release.tar.gz\n")
	defer server.Close()

	cfg, currentTarget, candidate := testNativeReleaseConfig(t, server.URL, version)
	updater, calls := testUpdater(server, cfg)
	err := updater.Run(&Job{}, version)
	if err == nil || !strings.Contains(err.Error(), "does not match") {
		t.Fatalf("expected checksum mismatch, got %v", err)
	}
	assertPrePublishFailure(t, cfg.McwebRoot, currentTarget, candidate, *calls)
}

func TestNativeReleaseUpdateHTTPFailureFailsBeforePublish(t *testing.T) {
	const version = "v2-http"
	server := httptest.NewServer(http.NotFoundHandler())
	defer server.Close()

	cfg, currentTarget, candidate := testNativeReleaseConfig(t, server.URL, version)
	updater, calls := testUpdater(server, cfg)
	err := updater.Run(&Job{}, version)
	if err == nil || !strings.Contains(err.Error(), "HTTP 404") {
		t.Fatalf("expected release server failure, got %v", err)
	}
	assertPrePublishFailure(t, cfg.McwebRoot, currentTarget, candidate, *calls)
}

func TestNativeReleaseUpdateRejectsUnsafeArchiveBeforePublish(t *testing.T) {
	const version = "v3"
	archive := buildReleaseArchive(t, version, []testArchiveEntry{{
		name:     "mcweb-v3/../../escaped",
		body:     []byte("unsafe"),
		mode:     0o644,
		typeflag: tar.TypeReg,
	}})
	server := releaseServer(t, version, archive, checksumFor(archive))
	defer server.Close()

	cfg, currentTarget, candidate := testNativeReleaseConfig(t, server.URL, version)
	updater, calls := testUpdater(server, cfg)
	err := updater.Run(&Job{}, version)
	if err == nil || !strings.Contains(err.Error(), "unsafe path") {
		t.Fatalf("expected unsafe path rejection, got %v", err)
	}
	assertPrePublishFailure(t, cfg.McwebRoot, currentTarget, candidate, *calls)
	if _, statErr := os.Lstat(filepath.Join(filepath.Dir(filepath.Dir(candidate)), "escaped")); !os.IsNotExist(statErr) {
		t.Fatalf("unsafe archive escaped staging: %v", statErr)
	}
}

func TestNativeReleaseUpdateRejectsWrongArchiveRootBeforePublish(t *testing.T) {
	const version = "v3-root"
	archive := buildReleaseArchive(t, "different", nil)
	server := releaseServer(t, version, archive, checksumFor(archive))
	defer server.Close()

	cfg, currentTarget, candidate := testNativeReleaseConfig(t, server.URL, version)
	updater, calls := testUpdater(server, cfg)
	err := updater.Run(&Job{}, version)
	if err == nil || !strings.Contains(err.Error(), "outside the expected") {
		t.Fatalf("expected archive root rejection, got %v", err)
	}
	assertPrePublishFailure(t, cfg.McwebRoot, currentTarget, candidate, *calls)
}

func TestNativeReleaseUpdateRejectsLinksAndSpecialEntries(t *testing.T) {
	tests := []struct {
		name  string
		entry testArchiveEntry
	}{
		{name: "symbolic link", entry: testArchiveEntry{name: "mcweb-v4/link", mode: 0o777, typeflag: tar.TypeSymlink, linkname: "/etc/passwd"}},
		{name: "hard link", entry: testArchiveEntry{name: "mcweb-v4/link", mode: 0o777, typeflag: tar.TypeLink, linkname: "mcweb-v4/VERSION"}},
		{name: "fifo", entry: testArchiveEntry{name: "mcweb-v4/fifo", mode: 0o600, typeflag: tar.TypeFifo}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			archive := buildReleaseArchive(t, "v4", []testArchiveEntry{test.entry})
			server := releaseServer(t, "v4", archive, checksumFor(archive))
			defer server.Close()
			cfg, currentTarget, candidate := testNativeReleaseConfig(t, server.URL, "v4")
			updater, calls := testUpdater(server, cfg)
			err := updater.Run(&Job{}, "v4")
			if err == nil || !strings.Contains(err.Error(), "unsupported entry type") {
				t.Fatalf("expected special entry rejection, got %v", err)
			}
			assertPrePublishFailure(t, cfg.McwebRoot, currentTarget, candidate, *calls)
		})
	}
}

func TestNativeReleaseUpdateRejectsWrongVersionAndExistingCandidate(t *testing.T) {
	t.Run("wrong VERSION", func(t *testing.T) {
		const version = "v5"
		archive := buildReleaseArchiveWithVersionFile(t, version, "v-other", nil)
		server := releaseServer(t, version, archive, checksumFor(archive))
		defer server.Close()
		cfg, currentTarget, candidate := testNativeReleaseConfig(t, server.URL, version)
		updater, calls := testUpdater(server, cfg)
		err := updater.Run(&Job{}, version)
		if err == nil || !strings.Contains(err.Error(), "VERSION does not match") {
			t.Fatalf("expected VERSION mismatch, got %v", err)
		}
		assertPrePublishFailure(t, cfg.McwebRoot, currentTarget, candidate, *calls)
	})

	t.Run("existing candidate", func(t *testing.T) {
		cfg, currentTarget, candidate := testNativeReleaseConfig(t, "https://releases.example.invalid", "v6")
		if err := os.Mkdir(candidate, 0o755); err != nil {
			t.Fatal(err)
		}
		updater := newNativeReleaseUpdater(cfg)
		calls := 0
		updater.prepareOwner = func(string, string) error { return nil }
		updater.runCommand = func(*exec.Cmd) ([]byte, error) { calls++; return nil, nil }
		err := updater.Run(&Job{}, "v6")
		if err == nil || !strings.Contains(err.Error(), "already exists") {
			t.Fatalf("expected existing candidate rejection, got %v", err)
		}
		if got := mustCurrentTarget(t, cfg.McwebRoot); got != currentTarget || calls != 0 {
			t.Fatalf("current=%q calls=%d, want current=%q calls=0", got, calls, currentTarget)
		}
	})
}

func TestNativeReleaseUpdateCommandFailureKeepsCurrentAndCandidate(t *testing.T) {
	const version = "v7"
	archive := buildReleaseArchive(t, version, nil)
	server := releaseServer(t, version, archive, checksumFor(archive))
	defer server.Close()
	cfg, currentTarget, candidate := testNativeReleaseConfig(t, server.URL, version)
	updater := newNativeReleaseUpdater(cfg)
	updater.client = server.Client()
	updater.prepareOwner = func(string, string) error { return nil }
	updater.runCommand = func(*exec.Cmd) ([]byte, error) {
		return []byte("preflight failed"), errors.New("exit status 1")
	}

	err := updater.Run(&Job{}, version)
	if err == nil || !strings.Contains(err.Error(), "current release remains") {
		t.Fatalf("expected verified current-release failure, got %v", err)
	}
	if got := mustCurrentTarget(t, cfg.McwebRoot); got != currentTarget {
		t.Fatalf("current target changed from %q to %q", currentTarget, got)
	}
	if _, statErr := os.Stat(filepath.Join(candidate, "bin", "update")); statErr != nil {
		t.Fatalf("candidate should remain for inspection: %v", statErr)
	}
}

func TestNativeReleaseUpdateRejectsUnsafeInputsAndOversizeDownload(t *testing.T) {
	for _, version := range []string{"", ".", "..", "../v1", "v1/next", " v1", strings.Repeat("v", 129)} {
		if err := validateReleaseVersion(version); err == nil {
			t.Errorf("validateReleaseVersion(%q) unexpectedly succeeded", version)
		}
	}
	if _, _, err := releaseAssetURLs("http://releases.example.com/download", "v1"); err == nil {
		t.Fatal("public HTTP release URL unexpectedly accepted")
	}
	if _, _, err := releaseAssetURLs("https://user:password@releases.example.com/download", "v1"); err == nil {
		t.Fatal("credential-bearing release URL unexpectedly accepted")
	}
	if _, _, err := releaseAssetURLs("https://releases.example.com/download?token=secret", "v1"); err == nil {
		t.Fatal("query-bearing release URL unexpectedly accepted")
	}

	const version = "v8"
	archive := buildReleaseArchive(t, version, nil)
	server := releaseServer(t, version, archive, checksumFor(archive))
	defer server.Close()
	cfg, currentTarget, candidate := testNativeReleaseConfig(t, server.URL, version)
	updater, calls := testUpdater(server, cfg)
	updater.archiveLimit = int64(len(archive) - 1)
	err := updater.Run(&Job{}, version)
	if err == nil || !strings.Contains(err.Error(), "exceeds") {
		t.Fatalf("expected download limit rejection, got %v", err)
	}
	assertPrePublishFailure(t, cfg.McwebRoot, currentTarget, candidate, *calls)
}

func testNativeReleaseConfig(t *testing.T, releaseURL, version string) (*config.Config, string, string) {
	t.Helper()
	base := t.TempDir()
	releases := filepath.Join(base, "releases")
	old := filepath.Join(releases, "old")
	if err := os.MkdirAll(old, 0o755); err != nil {
		t.Fatal(err)
	}
	current := filepath.Join(base, "current")
	if err := os.Symlink(old, current); err != nil {
		t.Fatalf("create current release symlink: %v", err)
	}
	cfg := config.Default()
	cfg.McwebRoot = current
	cfg.McwebUser = "mcweb"
	cfg.McwebEnvFile = filepath.Join(base, "mcweb.env")
	cfg.HealthURL = "http://127.0.0.1:3999"
	cfg.ReleaseURL = releaseURL + "/download"
	return cfg, mustCurrentTarget(t, current), filepath.Join(releases, version)
}

func testUpdater(server *httptest.Server, cfg *config.Config) (*nativeReleaseUpdater, *int) {
	updater := newNativeReleaseUpdater(cfg)
	updater.client = server.Client()
	updater.prepareOwner = func(string, string) error { return nil }
	calls := 0
	updater.runCommand = func(*exec.Cmd) ([]byte, error) {
		calls++
		return nil, nil
	}
	return updater, &calls
}

func releaseServer(t *testing.T, version string, archive []byte, checksum string) *httptest.Server {
	t.Helper()
	assetPath := "/download/" + version + "/mcweb-" + version + ".tar.gz"
	return httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case assetPath:
			response.Header().Set("Content-Length", fmt.Sprintf("%d", len(archive)))
			_, _ = response.Write(archive)
		case assetPath + ".sha256":
			_, _ = response.Write([]byte(checksum))
		default:
			http.NotFound(response, request)
		}
	}))
}

func checksumFor(archive []byte) string {
	digest := sha256.Sum256(archive)
	return fmt.Sprintf("%x  mcweb.tar.gz\n", digest)
}

func buildReleaseArchive(t *testing.T, version string, extra []testArchiveEntry) []byte {
	t.Helper()
	return buildReleaseArchiveWithVersionFile(t, version, version, extra)
}

func buildReleaseArchiveWithVersionFile(t *testing.T, rootVersion, fileVersion string, extra []testArchiveEntry) []byte {
	t.Helper()
	root := "mcweb-" + rootVersion
	entries := []testArchiveEntry{
		{name: root, mode: 0o755, typeflag: tar.TypeDir},
		{name: root + "/bin", mode: 0o755, typeflag: tar.TypeDir},
		{name: root + "/public", mode: 0o755, typeflag: tar.TypeDir},
		{name: root + "/public/assets", mode: 0o755, typeflag: tar.TypeDir},
		{name: root + "/VERSION", body: []byte(fileVersion + "\n"), mode: 0o644, typeflag: tar.TypeReg},
		{name: root + "/Gemfile.lock", body: []byte("GEM\n"), mode: 0o644, typeflag: tar.TypeReg},
		{name: root + "/bin/rails", body: []byte("#!/bin/sh\n"), mode: 0o755, typeflag: tar.TypeReg},
		{name: root + "/bin/rollback", body: []byte("#!/bin/sh\n"), mode: 0o755, typeflag: tar.TypeReg},
		{name: root + "/bin/update", body: []byte("#!/bin/sh\n"), mode: 0o755, typeflag: tar.TypeReg},
	}
	entries = append(entries, extra...)
	var buffer bytes.Buffer
	gzipWriter := gzip.NewWriter(&buffer)
	tarWriter := tar.NewWriter(gzipWriter)
	for _, entry := range entries {
		header := &tar.Header{
			Name:     entry.name,
			Mode:     entry.mode,
			Size:     int64(len(entry.body)),
			Typeflag: entry.typeflag,
			Linkname: entry.linkname,
		}
		if err := tarWriter.WriteHeader(header); err != nil {
			t.Fatal(err)
		}
		if len(entry.body) > 0 {
			if _, err := tarWriter.Write(entry.body); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := tarWriter.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

func assertEnvironmentEntry(t *testing.T, environment []string, expected string) {
	t.Helper()
	for _, entry := range environment {
		if entry == expected {
			return
		}
	}
	t.Fatalf("command environment is missing %q", expected)
}

func assertPrePublishFailure(t *testing.T, current string, expectedTarget string, candidate string, commandCalls int) {
	t.Helper()
	if commandCalls != 0 {
		t.Fatalf("update command called %d times, want 0", commandCalls)
	}
	if got := mustCurrentTarget(t, current); got != expectedTarget {
		t.Fatalf("current target changed from %q to %q", expectedTarget, got)
	}
	if _, err := os.Lstat(candidate); !os.IsNotExist(err) {
		t.Fatalf("candidate was published after failure: %v", err)
	}
}

func mustCurrentTarget(t *testing.T, current string) string {
	t.Helper()
	target, err := currentReleaseTarget(current)
	if err != nil {
		t.Fatal(err)
	}
	return target
}
