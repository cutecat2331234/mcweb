package worldstore

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sort"
	"time"
)

type ManifestEntry struct {
	Path   string `json:"path"`
	Type   string `json:"type"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256,omitempty"`
}

type Manifest struct {
	ManifestVersion    int             `json:"manifest_version"`
	SafetyProfile      string          `json:"safety_profile"`
	BackupID           string          `json:"backup_id"`
	ServerID           string          `json:"server_id"`
	NodeID             string          `json:"node_id"`
	Purpose            string          `json:"purpose"`
	RequestDigest      string          `json:"request_digest"`
	CreatedAt          time.Time       `json:"created_at"`
	ArchiveFormat      string          `json:"archive_format"`
	ArchiveSHA256      string          `json:"archive_sha256"`
	ManifestDigest     string          `json:"manifest_digest,omitempty"`
	ArchiveBytes       int64           `json:"archive_bytes"`
	UncompressedBytes  int64           `json:"uncompressed_bytes"`
	EntryCount         int64           `json:"entry_count"`
	DirectoryCount     int64           `json:"directory_count"`
	WorldRelativePath  string          `json:"world_relative_path"`
	SourceProcessState string          `json:"source_process_state"`
	SourceWorldState   string          `json:"source_world_state"`
	Entries            []ManifestEntry `json:"entries"`
}

func (manifest *Manifest) canonicalBytes() ([]byte, error) {
	copyValue := *manifest
	copyValue.ManifestDigest = ""
	return json.Marshal(&copyValue)
}

func (manifest *Manifest) SetDigest() error {
	data, err := manifest.canonicalBytes()
	if err != nil {
		return err
	}
	sum := sha256.Sum256(data)
	manifest.ManifestDigest = hex.EncodeToString(sum[:])
	return nil
}

func (manifest *Manifest) VerifyDigest() error {
	expected := manifest.ManifestDigest
	if err := validateSHA256(expected); err != nil {
		return fail("manifest_digest_invalid", err)
	}
	if err := manifest.SetDigest(); err != nil {
		return fail("manifest_digest_invalid", err)
	}
	if manifest.ManifestDigest != expected {
		return fail("manifest_digest_mismatch", nil)
	}
	return nil
}

func (manifest *Manifest) PublicSummary() *Manifest {
	copyValue := *manifest
	copyValue.Entries = nil
	return &copyValue
}

func validateManifest(manifest *Manifest, limits Limits) error {
	limits = NormalizeLimits(limits)
	if manifest.ManifestVersion != ManifestVersion || manifest.SafetyProfile != SafetyProfile ||
		manifest.ArchiveFormat != ArchiveFormat {
		return fail("manifest_profile_invalid", nil)
	}
	for _, value := range []string{manifest.BackupID, manifest.ServerID, manifest.NodeID} {
		if err := validateManagedID(value); err != nil {
			return fail("manifest_identity_invalid", err)
		}
	}
	if manifest.Purpose != "manual" && manifest.Purpose != "scheduled" && manifest.Purpose != "pre_restore" {
		return fail("manifest_purpose_invalid", nil)
	}
	if err := validateSHA256(manifest.RequestDigest); err != nil {
		return fail("manifest_request_digest_invalid", err)
	}
	if manifest.CreatedAt.IsZero() || manifest.CreatedAt.After(time.Now().UTC().Add(5*time.Minute)) {
		return fail("manifest_created_at_invalid", nil)
	}
	if _, err := ValidateRelativePath(manifest.WorldRelativePath, limits); err != nil {
		return err
	}
	if manifest.SourceProcessState != "stopped" ||
		(manifest.SourceWorldState != "present" && manifest.SourceWorldState != "absent") {
		return fail("manifest_source_state_invalid", nil)
	}
	if err := validateSHA256(manifest.ArchiveSHA256); err != nil {
		return fail("manifest_archive_digest_invalid", err)
	}
	if manifest.ArchiveBytes <= 0 || manifest.ArchiveBytes > limits.MaxArchiveBytes ||
		manifest.UncompressedBytes < 0 || manifest.UncompressedBytes > limits.MaxUncompressedBytes ||
		manifest.EntryCount < 0 || manifest.EntryCount > limits.MaxEntries ||
		manifest.DirectoryCount < 0 || manifest.DirectoryCount > limits.MaxDirectories ||
		int64(len(manifest.Entries)) != manifest.EntryCount {
		return fail("manifest_quota_invalid", nil)
	}

	index := newCollisionIndex()
	var total, directories int64
	previous := ""
	for position, entry := range manifest.Entries {
		path, err := ValidateRelativePath(entry.Path, limits)
		if err != nil || path != entry.Path {
			return fail("manifest_entry_path_invalid", err)
		}
		if position > 0 && previous >= entry.Path {
			return fail("manifest_entry_order_invalid", nil)
		}
		previous = entry.Path
		switch entry.Type {
		case "directory":
			if entry.Size != 0 || entry.SHA256 != "" {
				return fail("manifest_directory_invalid", nil)
			}
			directories++
			if err := index.Add(entry.Path, true); err != nil {
				return err
			}
		case "file":
			if entry.Size < 0 || entry.Size > limits.MaxFileBytes || validateSHA256(entry.SHA256) != nil {
				return fail("manifest_file_invalid", nil)
			}
			total += entry.Size
			if total > limits.MaxUncompressedBytes {
				return fail("manifest_uncompressed_quota_exceeded", nil)
			}
			if err := index.Add(entry.Path, false); err != nil {
				return err
			}
		default:
			return fail("manifest_entry_type_invalid", nil)
		}
	}
	if total != manifest.UncompressedBytes || directories != manifest.DirectoryCount {
		return fail("manifest_summary_mismatch", nil)
	}
	return manifest.VerifyDigest()
}

func writeManifest(path string, manifest *Manifest) error {
	data, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	if _, err = file.Write(data); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return err
	}
	return closeErr
}

func readManifest(path string, limits Limits) (*Manifest, error) {
	file, err := openRegularNoFollow(path)
	if err != nil {
		return nil, fail("manifest_open_failed", err)
	}
	defer file.Close()

	maximum := NormalizeLimits(limits).MaxManifestBytes
	data, err := io.ReadAll(io.LimitReader(file, maximum+1))
	if err != nil {
		return nil, fail("manifest_read_failed", err)
	}
	if int64(len(data)) > maximum {
		return nil, fail("manifest_size_exceeded", nil)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var manifest Manifest
	if err := decoder.Decode(&manifest); err != nil {
		return nil, fail("manifest_decode_failed", err)
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return nil, fail("manifest_trailing_data", err)
	}
	if err := validateManifest(&manifest, limits); err != nil {
		return nil, err
	}
	return &manifest, nil
}

func ensureJSONEOF(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		if err == nil {
			return fmt.Errorf("additional JSON value")
		}
		return err
	}
	return nil
}

func digestFile(path string, maximum int64) (string, int64, error) {
	file, err := openRegularNoFollow(path)
	if err != nil {
		return "", 0, err
	}
	defer file.Close()
	hasher := sha256.New()
	written, err := io.Copy(hasher, io.LimitReader(file, maximum+1))
	if err != nil {
		return "", written, err
	}
	if written > maximum {
		return "", written, fail("file_size_exceeded", nil)
	}
	return hex.EncodeToString(hasher.Sum(nil)), written, nil
}

func sortManifestEntries(entries []ManifestEntry) {
	sort.Slice(entries, func(i, j int) bool { return entries[i].Path < entries[j].Path })
}
