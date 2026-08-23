package worldstore

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

const maximumInt64 = int64(1<<63 - 1)

func (store *Store) Restore(ctx context.Context, request RestoreRequest) (*RestoreResult, error) {
	store.operationMu.Lock()
	defer store.operationMu.Unlock()
	if err := store.validateRestoreRequest(request); err != nil {
		return nil, err
	}
	livePath, err := resolveWorldPath(request.WorkingDirectory, request.WorldRelativePath, store.limits)
	if err != nil {
		return nil, err
	}
	if pathsOverlap(livePath, store.backupRoot) || pathsOverlap(livePath, store.ledgerRoot) {
		return nil, fail("world_path_overlaps_managed_storage", nil)
	}
	ledger := store.ledger(request.PlanID)
	if ledger != nil {
		if !ledger.matches(request) || ledger.LivePath != livePath {
			return nil, fail("restore_idempotency_conflict", nil)
		}
		if ledger.Result != nil {
			result := *ledger.Result
			if result.RecoveryRequired {
				return &result, fail(result.ErrorCode, nil)
			}
			if result.ErrorCode != "" {
				return &result, fail(result.ErrorCode, nil)
			}
			return &result, nil
		}
	} else {
		if store.RecoveryRequired() {
			return nil, fail("world_restore_recovery_required", nil)
		}
		ledger = store.newLedger(request, livePath)
		if err := store.saveLedger(ledger); err != nil {
			return nil, err
		}
	}
	return store.resumeRestore(ctx, request, ledger)
}

func (store *Store) validateRestoreRequest(request RestoreRequest) error {
	for _, value := range []string{
		request.PlanID, request.ServerID, request.NodeID, request.BackupID, request.PreRestoreBackupID,
	} {
		if err := validateManagedID(value); err != nil {
			return err
		}
	}
	for _, value := range []string{
		request.PlanDigest, request.OperationPayloadDigest, request.BackupManifestDigest,
		request.ServerConfigurationDigest,
	} {
		if err := validateSHA256(value); err != nil {
			return fail("restore_digest_invalid", err)
		}
	}
	if request.NodeID != store.nodeID {
		return fail("restore_node_mismatch", nil)
	}
	configurationDigest, err := ServerConfigurationDigest(
		request.ServerID,
		request.NodeID,
		request.WorkingDirectory,
		request.WorldRelativePath,
		request.ProcessDriver,
		request.ProcessConfig,
	)
	if err != nil || configurationDigest != request.ServerConfigurationDigest {
		return fail("restore_server_configuration_mismatch", err)
	}
	if request.OperationDeliveryID == "" || len(request.OperationDeliveryID) > 128 {
		return fail("restore_delivery_id_invalid", nil)
	}
	clean, err := ValidateRelativePath(request.WorldRelativePath, store.limits)
	if err != nil || clean != request.WorldRelativePath {
		return fail("restore_world_path_invalid", err)
	}
	if request.CheckStopped == nil {
		return fail("restore_stopped_check_required", nil)
	}
	return nil
}

func (store *Store) resumeRestore(
	ctx context.Context,
	request RestoreRequest,
	ledger *RestoreLedger,
) (*RestoreResult, error) {
	selected, err := store.loadBackup(request.ServerID, request.BackupID, request.BackupManifestDigest)
	if err != nil {
		return store.finishSafeFailure(ledger, nil, err)
	}
	if selected.WorldRelativePath != request.WorldRelativePath {
		return store.finishSafeFailure(ledger, nil, fail("restore_backup_world_path_mismatch", nil))
	}

	preRestore := store.loadPreRestoreManifest(ledger)
	if err := request.CheckStopped(ctx); err != nil {
		return store.finishSafeFailure(ledger, preRestore, fail("server_process_not_stopped", err))
	}
	if result, handled := store.recoverInterruptedCutover(
		ctx, request.CheckStopped, ledger, selected, preRestore,
	); handled {
		return result, resultError(result)
	}
	if err := store.resetPreCutoverStaging(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := request.CheckStopped(ctx); err != nil {
		return store.finishSafeFailure(ledger, preRestore, fail("server_process_not_stopped", err))
	}
	ledger.setPhase("process_stopped")
	if err := store.saveLedger(ledger); err != nil {
		return nil, err
	}

	if err := store.preflightRestoreSpace(ctx, request, ledger.LivePath, selected); err != nil {
		return store.finishSafeFailure(ledger, preRestore, err)
	}
	ledger.setPhase("pre_snapshot_started")
	if err := store.saveLedger(ledger); err != nil {
		return nil, err
	}
	preRestore, err = store.createBackupLocked(ctx, BackupRequest{
		BackupID:          request.PreRestoreBackupID,
		ServerID:          request.ServerID,
		NodeID:            request.NodeID,
		Purpose:           "pre_restore",
		RequestDigest:     request.PlanDigest,
		WorkingDirectory:  request.WorkingDirectory,
		WorldRelativePath: request.WorldRelativePath,
		CheckStopped:      request.CheckStopped,
	})
	if err != nil {
		return store.finishSafeFailure(ledger, preRestore, err)
	}
	ledger.PreRestoreManifestDigest = preRestore.ManifestDigest
	ledger.setPhase("pre_snapshot_durable")
	if err := store.saveLedger(ledger); err != nil {
		return nil, err
	}

	if err := scanOrExtractArchive(
		selected,
		store.archivePath(request.ServerID, request.BackupID),
		"",
		store.limits,
	); err != nil {
		return store.finishSafeFailure(ledger, preRestore, err)
	}
	ledger.setPhase("archive_validated")
	if err := store.saveLedger(ledger); err != nil {
		return nil, err
	}
	if err := request.CheckStopped(ctx); err != nil {
		return store.finishSafeFailure(ledger, preRestore, fail("server_process_not_stopped", err))
	}

	ledger.setPhase("staging_started")
	if err := store.saveLedger(ledger); err != nil {
		return nil, err
	}
	if selected.SourceWorldState == "present" {
		if err := os.Mkdir(ledger.StagingPath, 0o700); err != nil {
			return store.finishSafeFailure(ledger, preRestore, fail("restore_staging_create_failed", err))
		}
		if err := syncDirectory(filepath.Dir(ledger.StagingPath)); err != nil {
			return store.finishSafeFailure(ledger, preRestore, fail("restore_staging_sync_failed", err))
		}
		if err := scanOrExtractArchive(
			selected,
			store.archivePath(request.ServerID, request.BackupID),
			ledger.StagingPath,
			store.limits,
		); err != nil {
			return store.finishSafeFailure(ledger, preRestore, err)
		}
	} else if err := scanOrExtractArchive(
		selected,
		store.archivePath(request.ServerID, request.BackupID),
		"",
		store.limits,
	); err != nil {
		return store.finishSafeFailure(ledger, preRestore, err)
	}
	if err := verifyTree(ctx, ledger.StagingPath, selected, true, store.limits); err != nil {
		return store.finishSafeFailure(ledger, preRestore, err)
	}
	ledger.setPhase("staging_verified")
	if err := store.saveLedger(ledger); err != nil {
		return nil, err
	}
	if err := request.CheckStopped(ctx); err != nil {
		return store.finishSafeFailure(ledger, preRestore, fail("server_process_not_stopped", err))
	}

	liveExists, err := pathExists(ledger.LivePath)
	if err != nil {
		return store.finishSafeFailure(ledger, preRestore, fail("restore_live_state_unreadable", err))
	}
	rollbackExists, err := pathExists(ledger.RollbackPath)
	if err != nil || rollbackExists {
		return store.markRecoveryRequired(ledger, preRestore, fail("restore_rollback_path_not_empty", err))
	}
	ledger.LiveWasAbsent = !liveExists
	if err := store.saveLedger(ledger); err != nil {
		return nil, err
	}
	if liveExists {
		if err := renameDirectory(ledger.LivePath, ledger.RollbackPath); err != nil {
			return store.handleCutoverFailure(ctx, request.CheckStopped, ledger, selected, preRestore, err)
		}
	}
	ledger.setPhase("live_preserved")
	if err := store.saveLedger(ledger); err != nil {
		return store.handleCutoverFailure(ctx, request.CheckStopped, ledger, selected, preRestore, err)
	}
	if err := request.CheckStopped(ctx); err != nil {
		return store.handleCutoverFailure(
			ctx, request.CheckStopped, ledger, selected, preRestore, fail("server_process_not_stopped", err),
		)
	}
	if selected.SourceWorldState == "present" {
		if err := renameDirectory(ledger.StagingPath, ledger.LivePath); err != nil {
			return store.handleCutoverFailure(ctx, request.CheckStopped, ledger, selected, preRestore, err)
		}
	}
	ledger.setPhase("replacement_installed")
	if err := store.saveLedger(ledger); err != nil {
		return store.handleCutoverFailure(ctx, request.CheckStopped, ledger, selected, preRestore, err)
	}
	if err := verifyTree(ctx, ledger.LivePath, selected, true, store.limits); err != nil {
		return store.handleCutoverFailure(ctx, request.CheckStopped, ledger, selected, preRestore, err)
	}
	ledger.setPhase("post_install_verified")
	if err := store.saveLedger(ledger); err != nil {
		return store.handleCutoverFailure(ctx, request.CheckStopped, ledger, selected, preRestore, err)
	}
	return store.finishSuccessfulRestore(ctx, request.CheckStopped, ledger, selected, preRestore)
}

func (store *Store) recoverInterruptedCutover(
	ctx context.Context,
	checkStopped CheckStopped,
	ledger *RestoreLedger,
	selected *Manifest,
	preRestore *Manifest,
) (*RestoreResult, bool) {
	liveExists, liveErr := pathExists(ledger.LivePath)
	rollbackExists, rollbackErr := pathExists(ledger.RollbackPath)
	if liveErr != nil || rollbackErr != nil {
		result, _ := store.markRecoveryRequired(ledger, preRestore, fail("restore_recovery_paths_unreadable", firstError(liveErr, rollbackErr)))
		return result, true
	}

	if rollbackExists {
		if liveExists == (selected.SourceWorldState == "present") &&
			verifyTree(ctx, ledger.LivePath, selected, true, store.limits) == nil {
			ledger.setPhase("post_install_verified")
			if err := store.saveLedger(ledger); err != nil {
				result, _ := store.markRecoveryRequired(ledger, preRestore, err)
				return result, true
			}
			result, err := store.finishSuccessfulRestore(ctx, checkStopped, ledger, selected, preRestore)
			if err != nil {
				return result, true
			}
			return result, true
		}
		result, _ := store.rollbackRestore(
			ctx, checkStopped, ledger, preRestore, fail("restore_interrupted_cutover", nil),
		)
		return result, true
	}

	if destructivePhase(ledger.Phase) {
		if liveExists == (selected.SourceWorldState == "present") &&
			ledger.Phase != "rollback_started" && ledger.Phase != "recovery_required" &&
			verifyTree(ctx, ledger.LivePath, selected, true, store.limits) == nil {
			result, _ := store.finishSuccessfulRestore(ctx, checkStopped, ledger, selected, preRestore)
			return result, true
		}
		if preRestore != nil && verifyTree(ctx, ledger.LivePath, preRestore, true, store.limits) == nil {
			result, _ := store.finishRolledBack(
				ledger, preRestore, fail("restore_interrupted_rollback", nil),
			)
			return result, true
		}
		if ledger.LiveWasAbsent {
			if liveExists == (selected.SourceWorldState == "present") &&
				verifyTree(ctx, ledger.LivePath, selected, true, store.limits) == nil {
				result, _ := store.finishSuccessfulRestore(ctx, checkStopped, ledger, selected, preRestore)
				return result, true
			}
			result, _ := store.rollbackRestore(
				ctx, checkStopped, ledger, preRestore, fail("restore_interrupted_cutover", nil),
			)
			return result, true
		}
		result, _ := store.markRecoveryRequired(ledger, preRestore, fail("restore_rollback_tree_missing", nil))
		return result, true
	}
	return nil, false
}

func (store *Store) resetPreCutoverStaging(ledger *RestoreLedger) error {
	failedExists, err := pathExists(ledger.FailedReplacementPath)
	if err != nil {
		return fail("restore_failed_replacement_state_unreadable", err)
	}
	if failedExists {
		return fail("restore_failed_replacement_path_not_empty", nil)
	}

	stagingExists, err := pathExists(ledger.StagingPath)
	if err != nil {
		return fail("restore_staging_state_unreadable", err)
	}
	if !stagingExists {
		return nil
	}
	if ledger.Phase != "staging_started" && ledger.Phase != "staging_verified" {
		return fail("restore_staging_path_not_empty", nil)
	}
	return removeAuxiliaryTree(ledger.LivePath, ledger.StagingPath, "staging", ledger.PlanID)
}

func (store *Store) preflightRestoreSpace(
	ctx context.Context,
	request RestoreRequest,
	livePath string,
	selected *Manifest,
) error {
	_, liveBytes, _, _, err := inspectSourceTree(ctx, livePath, store.limits)
	if err != nil {
		return err
	}
	const reserve int64 = 64 * 1024 * 1024
	workingRequired, overflow := addSpaceRequirement(selected.UncompressedBytes, reserve)
	if overflow {
		return fail("restore_space_requirement_overflow", nil)
	}
	backupRequired, overflow := addSpaceRequirement(liveBytes, reserve)
	if overflow {
		return fail("restore_space_requirement_overflow", nil)
	}
	serverBackupRoot, err := store.ensureServerBackupRoot(request.ServerID)
	if err != nil {
		return err
	}
	workingRoot := filepath.Dir(livePath)
	sharedFilesystem, err := sameFilesystem(workingRoot, serverBackupRoot)
	if err != nil {
		return fail("restore_filesystem_identity_check_failed", err)
	}
	if sharedFilesystem {
		combinedRequired, combinedOverflow := addSpaceRequirement(workingRequired, backupRequired)
		if combinedOverflow {
			return fail("restore_space_requirement_overflow", nil)
		}
		return requireAvailableSpace(workingRoot, combinedRequired)
	}
	if err := requireAvailableSpace(workingRoot, workingRequired); err != nil {
		return err
	}
	return requireAvailableSpace(serverBackupRoot, backupRequired)
}

func addSpaceRequirement(value, reserve int64) (int64, bool) {
	if value < 0 || reserve < 0 || value > maximumInt64-reserve {
		return 0, true
	}
	return value + reserve, false
}

func requireAvailableSpace(path string, required int64) error {
	available, err := availableBytes(path)
	if err != nil {
		return fail("restore_free_space_check_failed", err)
	}
	if required < 0 || uint64(required) > available {
		return fail("restore_insufficient_free_space", nil)
	}
	return nil
}

func (store *Store) handleCutoverFailure(
	ctx context.Context,
	checkStopped CheckStopped,
	ledger *RestoreLedger,
	selected *Manifest,
	preRestore *Manifest,
	cause error,
) (*RestoreResult, error) {
	if err := requireStopped(ctx, checkStopped); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, firstError(cause, err))
	}
	rollbackExists, err := pathExists(ledger.RollbackPath)
	if err == nil && (rollbackExists || ledger.LiveWasAbsent) {
		return store.rollbackRestore(ctx, checkStopped, ledger, preRestore, cause)
	}
	if err == nil && !destructivePhase(ledger.Phase) {
		return store.finishSafeFailure(ledger, preRestore, cause)
	}
	_ = selected
	return store.markRecoveryRequired(ledger, preRestore, firstError(cause, err))
}

func (store *Store) rollbackRestore(
	ctx context.Context,
	checkStopped CheckStopped,
	ledger *RestoreLedger,
	preRestore *Manifest,
	cause error,
) (*RestoreResult, error) {
	if err := requireStopped(ctx, checkStopped); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, firstError(cause, err))
	}
	if preRestore == nil {
		preRestore = store.loadPreRestoreManifest(ledger)
	}
	if preRestore == nil {
		return store.markRecoveryRequired(ledger, nil, fail("restore_pre_snapshot_unavailable", cause))
	}
	if verifyTree(ctx, ledger.LivePath, preRestore, true, store.limits) == nil {
		return store.finishRolledBack(ledger, preRestore, cause)
	}
	ledger.setPhase("rollback_started")
	if err := store.saveLedger(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := removeAuxiliaryTree(
		ledger.LivePath, ledger.FailedReplacementPath, "failed", ledger.PlanID,
	); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	liveExists, err := pathExists(ledger.LivePath)
	if err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if liveExists {
		if err := requireStopped(ctx, checkStopped); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
		if err := renameDirectory(ledger.LivePath, ledger.FailedReplacementPath); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
	}
	if !ledger.LiveWasAbsent {
		rollbackExists, err := pathExists(ledger.RollbackPath)
		if err != nil || !rollbackExists {
			return store.markRecoveryRequired(ledger, preRestore, fail("restore_rollback_tree_missing", err))
		}
		if err := requireStopped(ctx, checkStopped); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
		if err := renameDirectory(ledger.RollbackPath, ledger.LivePath); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
	}
	if err := verifyTree(ctx, ledger.LivePath, preRestore, true, store.limits); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := requireStopped(ctx, checkStopped); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := removeAuxiliaryTree(
		ledger.LivePath, ledger.FailedReplacementPath, "failed", ledger.PlanID,
	); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := removeAuxiliaryTree(
		ledger.LivePath, ledger.StagingPath, "staging", ledger.PlanID,
	); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	return store.finishRolledBack(ledger, preRestore, cause)
}

func (store *Store) finishSuccessfulRestore(
	ctx context.Context,
	checkStopped CheckStopped,
	ledger *RestoreLedger,
	selected *Manifest,
	preRestore *Manifest,
) (*RestoreResult, error) {
	if preRestore == nil || preRestore.ManifestDigest != ledger.PreRestoreManifestDigest {
		return store.markRecoveryRequired(ledger, preRestore, fail("restore_pre_snapshot_unavailable", nil))
	}
	if err := requireStopped(ctx, checkStopped); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := removeAuxiliaryTree(ledger.LivePath, ledger.RollbackPath, "rollback", ledger.PlanID); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := requireStopped(ctx, checkStopped); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := removeAuxiliaryTree(ledger.LivePath, ledger.FailedReplacementPath, "failed", ledger.PlanID); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	result := &RestoreResult{
		PlanID:                  ledger.PlanID,
		Phase:                   "completed",
		InstalledManifestDigest: selected.ManifestDigest,
		PreRestoreBackup:        preRestore.PublicSummary(),
		RolledBack:              false,
		RecoveryRequired:        false,
		StartedAt:               ledger.CreatedAt,
		CompletedAt:             time.Now().UTC(),
	}
	ledger.setPhase("completed")
	ledger.Result = result
	if err := store.saveLedger(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	return result, nil
}

func (store *Store) finishRolledBack(
	ledger *RestoreLedger,
	preRestore *Manifest,
	cause error,
) (*RestoreResult, error) {
	result := &RestoreResult{
		PlanID:           ledger.PlanID,
		Phase:            "rolled_back",
		PreRestoreBackup: preRestore.PublicSummary(),
		RolledBack:       true,
		RecoveryRequired: false,
		ErrorCode:        errorCode(cause, "world_restore_rolled_back"),
		StartedAt:        ledger.CreatedAt,
		CompletedAt:      time.Now().UTC(),
	}
	ledger.setPhase("rolled_back")
	ledger.Result = result
	if err := store.saveLedger(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	return result, fail(result.ErrorCode, cause)
}

func (store *Store) finishSafeFailure(
	ledger *RestoreLedger,
	preRestore *Manifest,
	cause error,
) (*RestoreResult, error) {
	cutoverStarted, evidenceErr := store.cutoverMayHaveStarted(ledger)
	if evidenceErr != nil || cutoverStarted {
		if evidenceErr != nil {
			cause = firstError(cause, evidenceErr)
		}
		return store.markRecoveryRequired(ledger, preRestore, cause)
	}
	_ = removeAuxiliaryTree(ledger.LivePath, ledger.StagingPath, "staging", ledger.PlanID)
	result := &RestoreResult{
		PlanID:           ledger.PlanID,
		Phase:            ledger.Phase,
		PreRestoreBackup: publicManifest(preRestore),
		RolledBack:       false,
		RecoveryRequired: false,
		ErrorCode:        errorCode(cause, "world_restore_failed"),
		StartedAt:        ledger.CreatedAt,
		CompletedAt:      time.Now().UTC(),
	}
	ledger.Result = result
	if err := store.saveLedger(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	return result, fail(result.ErrorCode, cause)
}

func (store *Store) cutoverMayHaveStarted(ledger *RestoreLedger) (bool, error) {
	if destructivePhase(ledger.Phase) {
		return true, nil
	}
	for _, path := range []string{ledger.RollbackPath, ledger.FailedReplacementPath} {
		exists, err := pathExists(path)
		if err != nil {
			return false, fail("restore_cutover_state_unreadable", err)
		}
		if exists {
			return true, nil
		}
	}
	return false, nil
}

func (store *Store) markRecoveryRequired(
	ledger *RestoreLedger,
	preRestore *Manifest,
	cause error,
) (*RestoreResult, error) {
	result := &RestoreResult{
		PlanID:           ledger.PlanID,
		Phase:            "recovery_required",
		PreRestoreBackup: publicManifest(preRestore),
		RolledBack:       false,
		RecoveryRequired: true,
		ErrorCode:        errorCode(cause, "world_restore_recovery_required"),
		StartedAt:        ledger.CreatedAt,
		CompletedAt:      time.Now().UTC(),
	}
	ledger.setPhase("recovery_required")
	ledger.Result = result
	if err := store.saveLedger(ledger); err != nil {
		return result, fail("restore_recovery_ledger_persist_failed", firstError(cause, err))
	}
	return result, fail(result.ErrorCode, cause)
}

func (store *Store) loadPreRestoreManifest(ledger *RestoreLedger) *Manifest {
	if ledger.PreRestoreManifestDigest == "" {
		return nil
	}
	manifest, err := store.loadBackup(
		ledger.ServerID, ledger.PreRestoreBackupID, ledger.PreRestoreManifestDigest,
	)
	if err != nil {
		return nil
	}
	return manifest
}

func destructivePhase(phase string) bool {
	switch phase {
	case "live_preserved", "replacement_installed", "post_install_verified", "rollback_started", "recovery_required":
		return true
	default:
		return false
	}
}

func publicManifest(manifest *Manifest) *Manifest {
	if manifest == nil {
		return nil
	}
	return manifest.PublicSummary()
}

func resultError(result *RestoreResult) error {
	if result == nil || result.ErrorCode == "" {
		return nil
	}
	return fail(result.ErrorCode, nil)
}

func firstError(values ...error) error {
	for _, value := range values {
		if value != nil {
			return value
		}
	}
	return fmt.Errorf("unknown restore failure")
}

func requireStopped(ctx context.Context, checkStopped CheckStopped) error {
	if checkStopped == nil {
		return fail("restore_stopped_check_required", nil)
	}
	if err := checkStopped(ctx); err != nil {
		return fail("server_process_not_stopped", err)
	}
	return nil
}
