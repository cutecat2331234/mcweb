package worldstore

import (
	"context"
	"os"
)

func (store *Store) ResolveRecovery(
	ctx context.Context,
	request RecoveryResolutionRequest,
) (*RestoreResult, error) {
	store.operationMu.Lock()
	defer store.operationMu.Unlock()

	if err := store.validateRecoveryResolutionRequest(request); err != nil {
		return nil, err
	}
	ledger := store.ledger(request.PlanID)
	if ledger == nil {
		return nil, fail("restore_resolution_ledger_missing", nil)
	}
	if err := store.validateRecoveryResolutionLedger(request, ledger); err != nil {
		return nil, err
	}
	if ledger.Result != nil && ledger.Result.RecoveryResolutionProof {
		if resolutionResultMatches(ledger.Result, request) {
			result := *ledger.Result
			return &result, resultError(&result)
		}
		return nil, fail("restore_resolution_idempotency_conflict", nil)
	}
	if !ledgerRequiresRecovery(ledger) && request.ResolutionAction != "reconcile" {
		return nil, fail("restore_resolution_not_required", nil)
	}
	if err := store.bindRecoveryResolution(ledger, request); err != nil {
		return nil, err
	}
	if err := requireStopped(ctx, request.CheckStopped); err != nil {
		return store.finishRecoveryResolutionFailure(ledger, request, nil, err)
	}

	selected, err := store.loadBackup(
		request.ServerID,
		request.BackupID,
		request.BackupManifestDigest,
	)
	if err != nil {
		return store.finishRecoveryResolutionFailure(ledger, request, nil, err)
	}
	if selected.WorldRelativePath != request.WorldRelativePath {
		return store.finishRecoveryResolutionFailure(
			ledger,
			request,
			nil,
			fail("restore_backup_world_path_mismatch", nil),
		)
	}
	preRestore, err := store.recoverPreRestoreManifest(request, ledger)
	if err != nil {
		return store.finishRecoveryResolutionFailure(ledger, request, nil, err)
	}
	if request.PreRestoreManifestDigest != "" &&
		(preRestore == nil || preRestore.ManifestDigest != request.PreRestoreManifestDigest) {
		return store.finishRecoveryResolutionFailure(
			ledger,
			request,
			preRestore,
			fail("restore_resolution_pre_snapshot_mismatch", nil),
		)
	}

	var result *RestoreResult
	var resultErr error
	var verifiedState string
	switch request.ResolutionAction {
	case "resume":
		result, resultErr = store.resumeRecovery(ctx, request.CheckStopped, ledger, selected, preRestore)
	case "rollback":
		result, resultErr = store.rollbackRestore(
			ctx,
			request.CheckStopped,
			ledger,
			preRestore,
			fail("restore_operator_requested_rollback", nil),
		)
	case "reconcile":
		result, resultErr = store.reconcileRecovery(ctx, request.CheckStopped, ledger, selected, preRestore)
	}
	if result != nil && !result.RecoveryRequired {
		if result.Phase == "completed" {
			verifiedState = "selected"
		} else if preRestore != nil && preRestore.SourceWorldState == "absent" {
			verifiedState = "original_absent"
		} else {
			verifiedState = "pre_restore"
		}
	}
	return store.finishRecoveryResolution(ledger, request, result, verifiedState, resultErr)
}

func (store *Store) validateRecoveryResolutionRequest(request RecoveryResolutionRequest) error {
	for _, value := range []string{
		request.ResolutionID,
		request.PlanID,
		request.ServerID,
		request.NodeID,
		request.BackupID,
		request.PreRestoreBackupID,
	} {
		if err := validateManagedID(value); err != nil {
			return fail("restore_resolution_identity_invalid", err)
		}
	}
	for _, value := range []string{
		request.ReasonDigest,
		request.OperationPayloadDigest,
		request.RecoveryCapabilityDigest,
		request.PlanDigest,
		request.BackupManifestDigest,
		request.ServerConfigurationDigest,
	} {
		if err := validateSHA256(value); err != nil {
			return fail("restore_resolution_digest_invalid", err)
		}
	}
	if request.PreRestoreManifestDigest != "" && validateSHA256(request.PreRestoreManifestDigest) != nil {
		return fail("restore_resolution_pre_snapshot_digest_invalid", nil)
	}
	if request.ResolutionAction != "resume" && request.ResolutionAction != "rollback" &&
		request.ResolutionAction != "reconcile" {
		return fail("restore_resolution_action_invalid", nil)
	}
	if request.NodeID != store.nodeID {
		return fail("restore_resolution_node_mismatch", nil)
	}
	if request.OperationDeliveryID == "" || len(request.OperationDeliveryID) > 128 {
		return fail("restore_resolution_delivery_invalid", nil)
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
	clean, err := ValidateRelativePath(request.WorldRelativePath, store.limits)
	if err != nil || clean != request.WorldRelativePath {
		return fail("restore_resolution_world_path_invalid", err)
	}
	if request.CheckStopped == nil {
		return fail("restore_stopped_check_required", nil)
	}
	return nil
}

func (store *Store) validateRecoveryResolutionLedger(
	request RecoveryResolutionRequest,
	ledger *RestoreLedger,
) error {
	livePath, err := resolveWorldPath(request.WorkingDirectory, request.WorldRelativePath, store.limits)
	if err != nil {
		return err
	}
	if ledger.PlanID != request.PlanID || ledger.PlanDigest != request.PlanDigest ||
		ledger.ServerID != request.ServerID || ledger.NodeID != request.NodeID ||
		ledger.BackupID != request.BackupID ||
		ledger.BackupManifestDigest != request.BackupManifestDigest ||
		ledger.PreRestoreBackupID != request.PreRestoreBackupID ||
		ledger.ServerConfigurationDigest != request.ServerConfigurationDigest ||
		ledger.LocalConfigurationDigest != configurationDigest(
			request.WorkingDirectory,
			request.WorldRelativePath,
		) || ledger.WorkingDirectory != request.WorkingDirectory ||
		ledger.WorldRelativePath != request.WorldRelativePath || ledger.LivePath != livePath {
		return fail("restore_resolution_ledger_contract_mismatch", nil)
	}
	if request.PreRestoreManifestDigest != "" && ledger.PreRestoreManifestDigest != "" &&
		ledger.PreRestoreManifestDigest != request.PreRestoreManifestDigest {
		return fail("restore_resolution_pre_snapshot_mismatch", nil)
	}
	return nil
}

func (store *Store) recoverPreRestoreManifest(
	request RecoveryResolutionRequest,
	ledger *RestoreLedger,
) (*Manifest, error) {
	expectedDigest := ledger.PreRestoreManifestDigest
	if request.PreRestoreManifestDigest != "" {
		expectedDigest = request.PreRestoreManifestDigest
	}
	manifest, err := store.loadBackup(
		request.ServerID,
		request.PreRestoreBackupID,
		expectedDigest,
	)
	if err != nil {
		return nil, fail("restore_resolution_pre_snapshot_unavailable", err)
	}
	if manifest.Purpose != "pre_restore" || manifest.RequestDigest != ledger.PlanDigest ||
		manifest.WorldRelativePath != ledger.WorldRelativePath {
		return nil, fail("restore_resolution_pre_snapshot_contract_mismatch", nil)
	}
	if ledger.PreRestoreManifestDigest == "" {
		ledger.PreRestoreManifestDigest = manifest.ManifestDigest
		if err := store.saveLedger(ledger); err != nil {
			return nil, fail("restore_resolution_pre_snapshot_bind_failed", err)
		}
	}
	return manifest, nil
}

func (store *Store) bindRecoveryResolution(
	ledger *RestoreLedger,
	request RecoveryResolutionRequest,
) error {
	if ledger.LastResolutionID == request.ResolutionID {
		if ledger.LastResolutionAction != request.ResolutionAction ||
			ledger.LastResolutionReasonDigest != request.ReasonDigest ||
			ledger.LastResolutionDeliveryID != request.OperationDeliveryID ||
			ledger.LastResolutionPayloadDigest != request.OperationPayloadDigest ||
			ledger.LastRecoveryCapabilityDigest != request.RecoveryCapabilityDigest {
			return fail("restore_resolution_idempotency_conflict", nil)
		}
		return nil
	}
	if ledger.Result != nil && ledger.Result.RecoveryRequired {
		copyResult := *ledger.Result
		copyResult.RecoveryResolutionProof = false
		copyResult.ResolutionID = ""
		copyResult.ResolutionAction = ""
		copyResult.VerifiedWorldState = ""
		copyResult.PlanDigest = ""
		copyResult.ServerConfigurationDigest = ""
		copyResult.WorldRelativePath = ""
		ledger.Result = &copyResult
	}
	ledger.LastResolutionID = request.ResolutionID
	ledger.LastResolutionAction = request.ResolutionAction
	ledger.LastResolutionReasonDigest = request.ReasonDigest
	ledger.LastResolutionDeliveryID = request.OperationDeliveryID
	ledger.LastResolutionPayloadDigest = request.OperationPayloadDigest
	ledger.LastRecoveryCapabilityDigest = request.RecoveryCapabilityDigest
	return store.saveLedger(ledger)
}

func (store *Store) reconcileRecovery(
	ctx context.Context,
	checkStopped CheckStopped,
	ledger *RestoreLedger,
	selected *Manifest,
	preRestore *Manifest,
) (*RestoreResult, error) {
	if preRestore == nil {
		return store.markRecoveryRequired(
			ledger,
			nil,
			fail("restore_pre_snapshot_unavailable", nil),
		)
	}
	if err := requireStopped(ctx, checkStopped); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	selectedMatches := verifyTree(ctx, ledger.LivePath, selected, true, store.limits) == nil
	preRestoreMatches := verifyTree(ctx, ledger.LivePath, preRestore, true, store.limits) == nil

	if selectedMatches {
		if err := store.verifyRollbackTreeIfPresent(ctx, ledger, preRestore); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
		if err := store.cleanupRecoveryAuxiliaries(ctx, checkStopped, ledger); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
		return store.finishSuccessfulRestore(ctx, checkStopped, ledger, selected, preRestore)
	}
	if preRestoreMatches {
		if err := store.verifyRollbackTreeIfPresent(ctx, ledger, preRestore); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
		if err := store.cleanupRecoveryAuxiliaries(ctx, checkStopped, ledger); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
		return store.finishRolledBack(
			ledger,
			preRestore,
			fail("restore_reconciled_pre_restore_state", nil),
		)
	}
	return store.markRecoveryRequired(
		ledger,
		preRestore,
		fail("restore_reconcile_world_state_unproven", nil),
	)
}

func (store *Store) resumeRecovery(
	ctx context.Context,
	checkStopped CheckStopped,
	ledger *RestoreLedger,
	selected *Manifest,
	preRestore *Manifest,
) (*RestoreResult, error) {
	if preRestore == nil {
		return store.markRecoveryRequired(
			ledger,
			nil,
			fail("restore_pre_snapshot_unavailable", nil),
		)
	}
	if err := requireStopped(ctx, checkStopped); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if verifyTree(ctx, ledger.LivePath, selected, true, store.limits) == nil {
		if err := store.verifyRollbackTreeIfPresent(ctx, ledger, preRestore); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
		if err := store.cleanupRecoveryAuxiliaries(ctx, checkStopped, ledger); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
		return store.finishSuccessfulRestore(ctx, checkStopped, ledger, selected, preRestore)
	}

	rollbackExists, err := pathExists(ledger.RollbackPath)
	if err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if rollbackExists {
		if preRestore.SourceWorldState == "absent" ||
			verifyTree(ctx, ledger.RollbackPath, preRestore, true, store.limits) != nil {
			return store.markRecoveryRequired(
				ledger,
				preRestore,
				fail("restore_rollback_tree_unproven", nil),
			)
		}
	} else if verifyTree(ctx, ledger.LivePath, preRestore, true, store.limits) != nil {
		return store.markRecoveryRequired(
			ledger,
			preRestore,
			fail("restore_live_and_rollback_state_unproven", nil),
		)
	}

	if err := store.cleanupRecoveryWorkPaths(ctx, checkStopped, ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	ledger.setPhase("staging_started")
	if err := store.saveLedger(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if selected.SourceWorldState == "present" {
		if err := os.Mkdir(ledger.StagingPath, 0o700); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, fail("restore_staging_create_failed", err))
		}
		if err := scanOrExtractArchive(
			selected,
			store.archivePath(ledger.ServerID, ledger.BackupID),
			ledger.StagingPath,
			store.limits,
		); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
	}
	if err := verifyTree(ctx, ledger.StagingPath, selected, true, store.limits); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	ledger.setPhase("staging_verified")
	if err := store.saveLedger(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := requireStopped(ctx, checkStopped); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}

	liveExists, err := pathExists(ledger.LivePath)
	if err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if !rollbackExists {
		ledger.LiveWasAbsent = preRestore.SourceWorldState == "absent"
		if liveExists {
			if err := renameDirectory(ledger.LivePath, ledger.RollbackPath); err != nil {
				return store.markRecoveryRequired(ledger, preRestore, err)
			}
		}
	} else if liveExists {
		if err := renameDirectory(ledger.LivePath, ledger.FailedReplacementPath); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
	}
	ledger.setPhase("live_preserved")
	if err := store.saveLedger(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := requireStopped(ctx, checkStopped); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if selected.SourceWorldState == "present" {
		if err := renameDirectory(ledger.StagingPath, ledger.LivePath); err != nil {
			return store.markRecoveryRequired(ledger, preRestore, err)
		}
	}
	ledger.setPhase("replacement_installed")
	if err := store.saveLedger(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	if err := verifyTree(ctx, ledger.LivePath, selected, true, store.limits); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	ledger.setPhase("post_install_verified")
	if err := store.saveLedger(ledger); err != nil {
		return store.markRecoveryRequired(ledger, preRestore, err)
	}
	return store.finishSuccessfulRestore(ctx, checkStopped, ledger, selected, preRestore)
}

func (store *Store) verifyRollbackTreeIfPresent(
	ctx context.Context,
	ledger *RestoreLedger,
	preRestore *Manifest,
) error {
	exists, err := pathExists(ledger.RollbackPath)
	if err != nil || !exists {
		return err
	}
	if preRestore.SourceWorldState == "absent" ||
		verifyTree(ctx, ledger.RollbackPath, preRestore, true, store.limits) != nil {
		return fail("restore_rollback_tree_unproven", nil)
	}
	return nil
}

func (store *Store) cleanupRecoveryWorkPaths(
	ctx context.Context,
	checkStopped CheckStopped,
	ledger *RestoreLedger,
) error {
	for _, item := range []struct {
		path   string
		marker string
	}{
		{path: ledger.StagingPath, marker: "staging"},
		{path: ledger.FailedReplacementPath, marker: "failed"},
	} {
		if err := requireStopped(ctx, checkStopped); err != nil {
			return err
		}
		if err := removeAuxiliaryTree(ledger.LivePath, item.path, item.marker, ledger.PlanID); err != nil {
			return err
		}
	}
	return nil
}

func (store *Store) cleanupRecoveryAuxiliaries(
	ctx context.Context,
	checkStopped CheckStopped,
	ledger *RestoreLedger,
) error {
	if err := store.cleanupRecoveryWorkPaths(ctx, checkStopped, ledger); err != nil {
		return err
	}
	if err := requireStopped(ctx, checkStopped); err != nil {
		return err
	}
	return removeAuxiliaryTree(ledger.LivePath, ledger.RollbackPath, "rollback", ledger.PlanID)
}

func (store *Store) finishRecoveryResolutionFailure(
	ledger *RestoreLedger,
	request RecoveryResolutionRequest,
	preRestore *Manifest,
	cause error,
) (*RestoreResult, error) {
	result, resultErr := store.markRecoveryRequired(ledger, preRestore, cause)
	return store.finishRecoveryResolution(ledger, request, result, "", resultErr)
}

func (store *Store) finishRecoveryResolution(
	ledger *RestoreLedger,
	request RecoveryResolutionRequest,
	result *RestoreResult,
	verifiedState string,
	resultErr error,
) (*RestoreResult, error) {
	if result == nil {
		return store.finishRecoveryResolutionFailure(
			ledger,
			request,
			store.loadPreRestoreManifest(ledger),
			firstError(resultErr, fail("restore_resolution_result_missing", nil)),
		)
	}
	result.ResolutionID = request.ResolutionID
	result.ResolutionAction = request.ResolutionAction
	result.PlanDigest = ledger.PlanDigest
	result.ServerConfigurationDigest = ledger.ServerConfigurationDigest
	result.WorldRelativePath = ledger.WorldRelativePath
	result.VerifiedWorldState = verifiedState
	result.RecoveryResolutionProof = !result.RecoveryRequired &&
		(result.Phase == "completed" || result.Phase == "rolled_back") && verifiedState != ""
	ledger.Result = result
	if err := store.saveLedger(ledger); err != nil {
		result.RecoveryResolutionProof = false
		return result, fail("restore_resolution_proof_persist_failed", firstError(resultErr, err))
	}
	return result, resultErr
}

func resolutionResultMatches(result *RestoreResult, request RecoveryResolutionRequest) bool {
	return result.ResolutionID == request.ResolutionID &&
		result.ResolutionAction == request.ResolutionAction &&
		result.PlanID == request.PlanID && result.PlanDigest == request.PlanDigest &&
		result.ServerConfigurationDigest == request.ServerConfigurationDigest &&
		result.WorldRelativePath == request.WorldRelativePath
}
