package worldstore

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const archiveFileName = "world.tar.gz"
const manifestFileName = "manifest.json"

type Store struct {
	backupRoot  string
	ledgerRoot  string
	nodeID      string
	limits      Limits
	operationMu sync.Mutex
	ledgerMu    sync.RWMutex
	ledgers     map[string]*RestoreLedger
}

func New(backupRoot, ledgerRoot, nodeID string, limits Limits) (*Store, error) {
	if backupRoot == "" || ledgerRoot == "" {
		return nil, fail("world_store_root_required", nil)
	}
	if err := validateManagedID(nodeID); err != nil {
		return nil, fail("world_store_node_id_invalid", err)
	}
	absoluteBackupRoot, err := preparePrivateRoot(backupRoot)
	if err != nil {
		return nil, fail("world_backup_root_unavailable", err)
	}
	absoluteLedgerRoot, err := preparePrivateRoot(ledgerRoot)
	if err != nil {
		return nil, fail("world_restore_ledger_root_unavailable", err)
	}
	if pathsOverlap(absoluteBackupRoot, absoluteLedgerRoot) {
		return nil, fail("world_store_roots_overlap", nil)
	}
	store := &Store{
		backupRoot: absoluteBackupRoot,
		ledgerRoot: absoluteLedgerRoot,
		nodeID:     nodeID,
		limits:     NormalizeLimits(limits),
		ledgers:    make(map[string]*RestoreLedger),
	}
	if err := store.loadLedgers(); err != nil {
		return nil, err
	}
	return store, nil
}

func preparePrivateRoot(path string) (string, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	if err := ensureSafeCreationAncestors(absolute); err != nil {
		return "", err
	}
	if err := os.MkdirAll(absolute, 0o700); err != nil {
		return "", err
	}
	if err := os.Chmod(absolute, 0o700); err != nil {
		return "", err
	}
	if err := ensureSafeConfiguredPath(absolute); err != nil {
		return "", err
	}
	return absolute, nil
}

func (store *Store) Limits() Limits { return store.limits }

func (store *Store) CreateBackup(ctx context.Context, request BackupRequest) (*Manifest, error) {
	store.operationMu.Lock()
	defer store.operationMu.Unlock()
	if store.RecoveryRequired() {
		return nil, fail("world_restore_recovery_required", nil)
	}
	return store.createBackupLocked(ctx, request)
}

func (store *Store) createBackupLocked(ctx context.Context, request BackupRequest) (*Manifest, error) {
	if err := store.validateBackupRequest(request); err != nil {
		return nil, err
	}
	if err := request.CheckStopped(ctx); err != nil {
		return nil, fail("server_process_not_stopped", err)
	}
	worldPath, err := resolveWorldPath(request.WorkingDirectory, request.WorldRelativePath, store.limits)
	if err != nil {
		return nil, err
	}
	if pathsOverlap(worldPath, store.backupRoot) || pathsOverlap(worldPath, store.ledgerRoot) {
		return nil, fail("world_path_overlaps_managed_storage", nil)
	}

	serverRoot, err := store.ensureServerBackupRoot(request.ServerID)
	if err != nil {
		return nil, err
	}
	finalDirectory := store.backupDirectory(request.ServerID, request.BackupID)
	existing, err := pathExists(finalDirectory)
	if err != nil {
		return nil, fail("backup_existing_state_unreadable", err)
	}
	if existing {
		manifest, loadErr := store.loadBackup(request.ServerID, request.BackupID, "")
		if loadErr != nil {
			return nil, fail("backup_existing_state_invalid", loadErr)
		}
		if manifest.Purpose != request.Purpose || manifest.RequestDigest != request.RequestDigest ||
			manifest.WorldRelativePath != request.WorldRelativePath {
			return nil, fail("backup_idempotency_conflict", nil)
		}
		return manifest.PublicSummary(), nil
	}
	temporary, err := os.MkdirTemp(serverRoot, "."+request.BackupID+".pending-")
	if err != nil {
		return nil, fail("backup_staging_create_failed", err)
	}
	keepTemporary := false
	defer func() {
		if !keepTemporary {
			_ = os.RemoveAll(temporary)
		}
	}()
	if err := os.Chmod(temporary, 0o700); err != nil {
		return nil, fail("backup_staging_permission_failed", err)
	}

	archivePath := filepath.Join(temporary, archiveFileName)
	entries, uncompressedBytes, directoryCount, sourceState, err := writeManagedArchive(
		ctx, archivePath, worldPath, store.limits,
	)
	if err != nil {
		return nil, err
	}
	archiveDigest, archiveBytes, err := digestFile(archivePath, store.limits.MaxArchiveBytes)
	if err != nil {
		return nil, fail("backup_archive_digest_failed", err)
	}
	if uncompressedBytes > 0 && archiveBytes > 0 &&
		float64(uncompressedBytes)/float64(archiveBytes) > store.limits.MaxExpansionRatio {
		return nil, fail("backup_expansion_ratio_exceeded", nil)
	}

	manifest := &Manifest{
		ManifestVersion:    ManifestVersion,
		SafetyProfile:      SafetyProfile,
		BackupID:           request.BackupID,
		ServerID:           request.ServerID,
		NodeID:             request.NodeID,
		Purpose:            request.Purpose,
		RequestDigest:      request.RequestDigest,
		CreatedAt:          time.Now().UTC(),
		ArchiveFormat:      ArchiveFormat,
		ArchiveSHA256:      archiveDigest,
		ArchiveBytes:       archiveBytes,
		UncompressedBytes:  uncompressedBytes,
		EntryCount:         int64(len(entries)),
		DirectoryCount:     directoryCount,
		WorldRelativePath:  request.WorldRelativePath,
		SourceProcessState: "stopped",
		SourceWorldState:   sourceState,
		Entries:            entries,
	}
	if err := manifest.SetDigest(); err != nil {
		return nil, fail("manifest_digest_failed", err)
	}
	if err := validateManifest(manifest, store.limits); err != nil {
		return nil, err
	}
	if err := writeManifest(filepath.Join(temporary, manifestFileName), manifest); err != nil {
		return nil, fail("manifest_write_failed", err)
	}
	if err := syncDirectory(temporary); err != nil {
		return nil, fail("backup_staging_sync_failed", err)
	}
	if err := request.CheckStopped(ctx); err != nil {
		return nil, fail("server_process_not_stopped", err)
	}

	if err := renameDirectory(temporary, finalDirectory); err != nil {
		if existing, loadErr := store.loadBackup(request.ServerID, request.BackupID, ""); loadErr == nil {
			if existing.ManifestDigest != manifest.ManifestDigest {
				return nil, fail("backup_idempotency_conflict", err)
			}
			return existing.PublicSummary(), nil
		}
		return nil, fail("backup_publish_failed", err)
	}
	keepTemporary = true
	verified, err := store.loadBackup(request.ServerID, request.BackupID, manifest.ManifestDigest)
	if err != nil {
		return nil, err
	}
	return verified.PublicSummary(), nil
}

func (store *Store) validateBackupRequest(request BackupRequest) error {
	for _, value := range []string{request.BackupID, request.ServerID, request.NodeID} {
		if err := validateManagedID(value); err != nil {
			return err
		}
	}
	if request.NodeID != store.nodeID {
		return fail("backup_node_mismatch", nil)
	}
	if request.Purpose != "manual" && request.Purpose != "scheduled" && request.Purpose != "pre_restore" {
		return fail("backup_purpose_invalid", nil)
	}
	if err := validateSHA256(request.RequestDigest); err != nil {
		return fail("backup_request_digest_invalid", err)
	}
	clean, err := ValidateRelativePath(request.WorldRelativePath, store.limits)
	if err != nil || clean != request.WorldRelativePath {
		return fail("backup_world_path_invalid", err)
	}
	if request.CheckStopped == nil {
		return fail("backup_stopped_check_required", nil)
	}
	return nil
}

func (store *Store) ensureServerBackupRoot(serverID string) (string, error) {
	if err := validateManagedID(serverID); err != nil {
		return "", err
	}
	root := filepath.Join(store.backupRoot, serverID)
	if info, err := os.Lstat(root); err == nil {
		if unsafeFileInfo(info) || !info.IsDir() {
			return "", fail("backup_server_root_unsafe", nil)
		}
	} else if os.IsNotExist(err) {
		if err := os.Mkdir(root, 0o700); err != nil {
			return "", fail("backup_server_root_create_failed", err)
		}
		if err := syncDirectory(store.backupRoot); err != nil {
			return "", fail("backup_server_root_sync_failed", err)
		}
	} else {
		return "", fail("backup_server_root_unreadable", err)
	}
	return root, nil
}

func (store *Store) backupDirectory(serverID, backupID string) string {
	return filepath.Join(store.backupRoot, serverID, backupID)
}

func (store *Store) loadBackup(serverID, backupID, expectedManifestDigest string) (*Manifest, error) {
	if err := validateManagedID(serverID); err != nil {
		return nil, err
	}
	if err := validateManagedID(backupID); err != nil {
		return nil, err
	}
	directory := store.backupDirectory(serverID, backupID)
	info, err := os.Lstat(directory)
	if err != nil {
		return nil, fail("backup_not_found", err)
	}
	if unsafeFileInfo(info) || !info.IsDir() {
		return nil, fail("backup_directory_unsafe", nil)
	}
	manifest, err := readManifest(filepath.Join(directory, manifestFileName), store.limits)
	if err != nil {
		return nil, err
	}
	if manifest.ServerID != serverID || manifest.BackupID != backupID || manifest.NodeID != store.nodeID {
		return nil, fail("backup_manifest_identity_mismatch", nil)
	}
	if expectedManifestDigest != "" && manifest.ManifestDigest != expectedManifestDigest {
		return nil, fail("backup_manifest_digest_mismatch", nil)
	}
	if err := validateArchiveFile(filepath.Join(directory, archiveFileName), manifest, store.limits); err != nil {
		return nil, err
	}
	return manifest, nil
}

func (store *Store) archivePath(serverID, backupID string) string {
	return filepath.Join(store.backupDirectory(serverID, backupID), archiveFileName)
}

func configurationDigest(workingDirectory, worldRelativePath string) string {
	value := strings.Join([]string{filepath.Clean(workingDirectory), worldRelativePath}, "\x00")
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}
