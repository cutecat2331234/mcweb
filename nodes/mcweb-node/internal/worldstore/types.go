package worldstore

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

const (
	ManifestVersion = 1
	SafetyProfile   = "mcweb-world-restore-v1"
	ArchiveFormat   = "tar.gz"
)

type Limits struct {
	MaxArchiveBytes      int64   `yaml:"max_archive_bytes" json:"max_archive_bytes"`
	MaxManifestBytes     int64   `yaml:"max_manifest_bytes" json:"max_manifest_bytes"`
	MaxUncompressedBytes int64   `yaml:"max_uncompressed_bytes" json:"max_uncompressed_bytes"`
	MaxFileBytes         int64   `yaml:"max_file_bytes" json:"max_file_bytes"`
	MaxEntries           int64   `yaml:"max_entries" json:"max_entries"`
	MaxDirectories       int64   `yaml:"max_directories" json:"max_directories"`
	MaxDepth             int     `yaml:"max_depth" json:"max_depth"`
	MaxPathBytes         int     `yaml:"max_path_bytes" json:"max_path_bytes"`
	MaxExpansionRatio    float64 `yaml:"max_expansion_ratio" json:"max_expansion_ratio"`
}

func DefaultLimits() Limits {
	return Limits{
		MaxArchiveBytes:      64 * 1024 * 1024 * 1024,
		MaxManifestBytes:     256 * 1024 * 1024,
		MaxUncompressedBytes: 256 * 1024 * 1024 * 1024,
		MaxFileBytes:         64 * 1024 * 1024 * 1024,
		MaxEntries:           2_000_000,
		MaxDirectories:       1_000_000,
		MaxDepth:             64,
		MaxPathBytes:         1024,
		MaxExpansionRatio:    200,
	}
}

// NormalizeLimits fills omitted limits and clamps configured values to the
// built-in safety maxima. Local configuration may tighten but never raise them.
func NormalizeLimits(value Limits) Limits {
	maximum := DefaultLimits()
	value.MaxArchiveBytes = boundedInt64(value.MaxArchiveBytes, maximum.MaxArchiveBytes)
	value.MaxManifestBytes = boundedInt64(value.MaxManifestBytes, maximum.MaxManifestBytes)
	value.MaxUncompressedBytes = boundedInt64(value.MaxUncompressedBytes, maximum.MaxUncompressedBytes)
	value.MaxFileBytes = boundedInt64(value.MaxFileBytes, maximum.MaxFileBytes)
	value.MaxEntries = boundedInt64(value.MaxEntries, maximum.MaxEntries)
	value.MaxDirectories = boundedInt64(value.MaxDirectories, maximum.MaxDirectories)
	value.MaxDepth = boundedInt(value.MaxDepth, maximum.MaxDepth)
	value.MaxPathBytes = boundedInt(value.MaxPathBytes, maximum.MaxPathBytes)
	if value.MaxExpansionRatio <= 0 || value.MaxExpansionRatio > maximum.MaxExpansionRatio {
		value.MaxExpansionRatio = maximum.MaxExpansionRatio
	}
	return value
}

func boundedInt64(value, maximum int64) int64 {
	if value <= 0 || value > maximum {
		return maximum
	}
	return value
}

func boundedInt(value, maximum int) int {
	if value <= 0 || value > maximum {
		return maximum
	}
	return value
}

type CheckStopped func(context.Context) error

type BackupRequest struct {
	BackupID          string
	ServerID          string
	NodeID            string
	Purpose           string
	RequestDigest     string
	WorkingDirectory  string
	WorldRelativePath string
	CheckStopped      CheckStopped
}

type RestoreRequest struct {
	PlanID                    string
	PlanDigest                string
	OperationDeliveryID       string
	OperationPayloadDigest    string
	ServerID                  string
	NodeID                    string
	BackupID                  string
	BackupManifestDigest      string
	PreRestoreBackupID        string
	ServerConfigurationDigest string
	ProcessDriver             string
	ProcessConfig             map[string]interface{}
	WorkingDirectory          string
	WorldRelativePath         string
	CheckStopped              CheckStopped
}

func ServerConfigurationDigest(
	serverID string,
	nodeID string,
	workingDirectory string,
	worldRelativePath string,
	processDriver string,
	processConfig map[string]interface{},
) (string, error) {
	payload := map[string]interface{}{
		"server_id":           serverID,
		"node_id":             nodeID,
		"working_directory":   workingDirectory,
		"world_relative_path": worldRelativePath,
		"process_driver":      processDriver,
		"process_config":      processConfig,
	}
	encoded, err := railsCanonicalJSON(payload)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(encoded)
	return hex.EncodeToString(digest[:]), nil
}

func railsCanonicalJSON(value interface{}) ([]byte, error) {
	var buffer bytes.Buffer
	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return nil, err
	}
	encoded := bytes.TrimSuffix(buffer.Bytes(), []byte{'\n'})
	encoded = bytes.ReplaceAll(encoded, []byte(`\u2028`), []byte("\u2028"))
	encoded = bytes.ReplaceAll(encoded, []byte(`\u2029`), []byte("\u2029"))
	return encoded, nil
}

type RestoreResult struct {
	PlanID                  string    `json:"plan_id"`
	Phase                   string    `json:"phase"`
	InstalledManifestDigest string    `json:"installed_manifest_digest,omitempty"`
	PreRestoreBackup        *Manifest `json:"pre_restore_backup,omitempty"`
	RolledBack              bool      `json:"rolled_back"`
	RecoveryRequired        bool      `json:"recovery_required"`
	ErrorCode               string    `json:"error_code,omitempty"`
	StartedAt               time.Time `json:"started_at"`
	CompletedAt             time.Time `json:"completed_at"`
}

type Error struct {
	Code string
	Err  error
}

func (e *Error) Error() string {
	if e.Err == nil {
		return e.Code
	}
	return fmt.Sprintf("%s: %v", e.Code, e.Err)
}

func (e *Error) Unwrap() error { return e.Err }

func errorCode(err error, fallback string) string {
	var operationError *Error
	if errors.As(err, &operationError) && operationError.Code != "" {
		return operationError.Code
	}
	return fallback
}

func Code(err error) string {
	return errorCode(err, "managed_world_operation_failed")
}

func fail(code string, err error) error {
	return &Error{Code: code, Err: err}
}
