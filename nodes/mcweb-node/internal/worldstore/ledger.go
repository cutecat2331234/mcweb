package worldstore

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const ledgerVersion = 1
const maxLedgerBytes int64 = 1024 * 1024

var restorePhases = map[string]struct{}{
	"accepted": {}, "process_stopped": {}, "pre_snapshot_started": {}, "pre_snapshot_durable": {},
	"archive_validated": {}, "staging_started": {}, "staging_verified": {}, "live_preserved": {},
	"replacement_installed": {}, "post_install_verified": {}, "rollback_started": {}, "rolled_back": {},
	"completed": {}, "recovery_required": {},
}

type RestoreLedger struct {
	Version                      int            `json:"version"`
	PlanID                       string         `json:"plan_id"`
	PlanDigest                   string         `json:"plan_digest"`
	OperationDeliveryID          string         `json:"operation_delivery_id"`
	OperationPayloadDigest       string         `json:"operation_payload_digest"`
	ServerID                     string         `json:"server_id"`
	NodeID                       string         `json:"node_id"`
	BackupID                     string         `json:"backup_id"`
	BackupManifestDigest         string         `json:"backup_manifest_digest"`
	PreRestoreBackupID           string         `json:"pre_restore_backup_id"`
	ServerConfigurationDigest    string         `json:"server_configuration_digest"`
	LocalConfigurationDigest     string         `json:"local_configuration_digest"`
	WorkingDirectory             string         `json:"working_directory"`
	WorldRelativePath            string         `json:"world_relative_path"`
	LivePath                     string         `json:"live_path"`
	StagingPath                  string         `json:"staging_path"`
	RollbackPath                 string         `json:"rollback_path"`
	FailedReplacementPath        string         `json:"failed_replacement_path"`
	LiveWasAbsent                bool           `json:"live_was_absent"`
	Phase                        string         `json:"phase"`
	PreRestoreManifestDigest     string         `json:"pre_restore_manifest_digest,omitempty"`
	Result                       *RestoreResult `json:"result,omitempty"`
	LastResolutionID             string         `json:"last_resolution_id,omitempty"`
	LastResolutionAction         string         `json:"last_resolution_action,omitempty"`
	LastResolutionReasonDigest   string         `json:"last_resolution_reason_digest,omitempty"`
	LastResolutionDeliveryID     string         `json:"last_resolution_delivery_id,omitempty"`
	LastResolutionPayloadDigest  string         `json:"last_resolution_payload_digest,omitempty"`
	LastRecoveryCapabilityDigest string         `json:"last_recovery_capability_digest,omitempty"`
	CreatedAt                    time.Time      `json:"created_at"`
	UpdatedAt                    time.Time      `json:"updated_at"`
}

func (store *Store) loadLedgers() error {
	entries, err := os.ReadDir(store.ledgerRoot)
	if err != nil {
		return fail("restore_ledger_list_failed", err)
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") || strings.HasSuffix(entry.Name(), ".next.json") {
			continue
		}
		planID := strings.TrimSuffix(entry.Name(), ".json")
		if err := validateManagedID(planID); err != nil {
			return fail("restore_ledger_filename_invalid", err)
		}
		ledger, err := store.readLedger(filepath.Join(store.ledgerRoot, entry.Name()))
		if err != nil {
			return err
		}
		if ledger.PlanID != planID {
			return fail("restore_ledger_identity_mismatch", nil)
		}
		store.ledgers[planID] = ledger
	}
	return nil
}

func (store *Store) readLedger(path string) (*RestoreLedger, error) {
	file, err := openRegularNoFollow(path)
	if err != nil {
		return nil, fail("restore_ledger_open_failed", err)
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxLedgerBytes+1))
	if err != nil {
		return nil, fail("restore_ledger_read_failed", err)
	}
	if int64(len(data)) > maxLedgerBytes {
		return nil, fail("restore_ledger_size_exceeded", nil)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var ledger RestoreLedger
	if err := decoder.Decode(&ledger); err != nil {
		return nil, fail("restore_ledger_decode_failed", err)
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return nil, fail("restore_ledger_trailing_data", err)
	}
	if err := store.validateLedger(&ledger); err != nil {
		return nil, err
	}
	return &ledger, nil
}

func (store *Store) validateLedger(ledger *RestoreLedger) error {
	if ledger.Version != ledgerVersion || ledger.NodeID != store.nodeID {
		return fail("restore_ledger_version_or_node_invalid", nil)
	}
	for _, value := range []string{
		ledger.PlanID, ledger.ServerID, ledger.NodeID, ledger.BackupID, ledger.PreRestoreBackupID,
	} {
		if err := validateManagedID(value); err != nil {
			return fail("restore_ledger_identity_invalid", err)
		}
	}
	for _, value := range []string{
		ledger.PlanDigest, ledger.OperationPayloadDigest, ledger.BackupManifestDigest,
		ledger.ServerConfigurationDigest, ledger.LocalConfigurationDigest,
	} {
		if err := validateSHA256(value); err != nil {
			return fail("restore_ledger_digest_invalid", err)
		}
	}
	if ledger.OperationDeliveryID == "" || len(ledger.OperationDeliveryID) > 128 {
		return fail("restore_ledger_delivery_invalid", nil)
	}
	if _, ok := restorePhases[ledger.Phase]; !ok {
		return fail("restore_ledger_phase_invalid", nil)
	}
	cleanWorldPath, err := ValidateRelativePath(ledger.WorldRelativePath, store.limits)
	if err != nil {
		return err
	}
	if cleanWorldPath != ledger.WorldRelativePath {
		return fail("restore_ledger_world_path_invalid", nil)
	}
	if configurationDigest(ledger.WorkingDirectory, ledger.WorldRelativePath) != ledger.LocalConfigurationDigest {
		return fail("restore_ledger_local_configuration_mismatch", nil)
	}
	expectedLivePath, err := resolveWorldPath(ledger.WorkingDirectory, ledger.WorldRelativePath, store.limits)
	if err != nil || filepath.Clean(expectedLivePath) != filepath.Clean(ledger.LivePath) {
		return fail("restore_ledger_live_path_mismatch", err)
	}
	if ledger.LivePath == "" || ledger.StagingPath == "" || ledger.RollbackPath == "" ||
		ledger.FailedReplacementPath == "" {
		return fail("restore_ledger_paths_missing", nil)
	}
	for marker, path := range map[string]string{
		"staging":  ledger.StagingPath,
		"rollback": ledger.RollbackPath,
		"failed":   ledger.FailedReplacementPath,
	} {
		if err := safeAuxiliaryPath(ledger.LivePath, path, marker, ledger.PlanID); err != nil {
			return err
		}
	}
	if ledger.PreRestoreManifestDigest != "" && validateSHA256(ledger.PreRestoreManifestDigest) != nil {
		return fail("restore_ledger_pre_snapshot_digest_invalid", nil)
	}
	if destructivePhase(ledger.Phase) && ledger.Phase != "recovery_required" &&
		ledger.PreRestoreManifestDigest == "" {
		return fail("restore_ledger_pre_snapshot_missing", nil)
	}
	if err := validateResolutionBinding(ledger); err != nil {
		return err
	}
	if err := validateLedgerResult(ledger); err != nil {
		return err
	}
	return nil
}

func validateResolutionBinding(ledger *RestoreLedger) error {
	values := []string{
		ledger.LastResolutionID,
		ledger.LastResolutionAction,
		ledger.LastResolutionReasonDigest,
		ledger.LastResolutionDeliveryID,
		ledger.LastResolutionPayloadDigest,
		ledger.LastRecoveryCapabilityDigest,
	}
	present := 0
	for _, value := range values {
		if value != "" {
			present++
		}
	}
	if present == 0 {
		return nil
	}
	if present != len(values) || validateManagedID(ledger.LastResolutionID) != nil ||
		(ledger.LastResolutionAction != "resume" && ledger.LastResolutionAction != "rollback" &&
			ledger.LastResolutionAction != "reconcile") ||
		validateSHA256(ledger.LastResolutionReasonDigest) != nil ||
		validateSHA256(ledger.LastResolutionPayloadDigest) != nil ||
		validateSHA256(ledger.LastRecoveryCapabilityDigest) != nil ||
		len(ledger.LastResolutionDeliveryID) > 128 {
		return fail("restore_ledger_resolution_binding_invalid", nil)
	}
	return nil
}

func validateLedgerResult(ledger *RestoreLedger) error {
	result := ledger.Result
	if result == nil {
		if ledger.Phase == "completed" || ledger.Phase == "rolled_back" {
			return fail("restore_ledger_terminal_result_missing", nil)
		}
		return nil
	}
	if result.PlanID != ledger.PlanID || result.Phase == "" || result.StartedAt.IsZero() ||
		result.CompletedAt.IsZero() || result.CompletedAt.Before(result.StartedAt) {
		return fail("restore_ledger_result_invalid", nil)
	}
	if result.RolledBack && result.RecoveryRequired {
		return fail("restore_ledger_result_flags_invalid", nil)
	}
	if result.InstalledManifestDigest != "" && validateSHA256(result.InstalledManifestDigest) != nil {
		return fail("restore_ledger_result_digest_invalid", nil)
	}
	if result.PreRestoreBackup != nil {
		manifest := result.PreRestoreBackup
		if manifest.BackupID != ledger.PreRestoreBackupID || manifest.ServerID != ledger.ServerID ||
			manifest.NodeID != ledger.NodeID || manifest.ManifestDigest != ledger.PreRestoreManifestDigest ||
			validateSHA256(manifest.ManifestDigest) != nil || len(manifest.Entries) != 0 {
			return fail("restore_ledger_result_pre_snapshot_invalid", nil)
		}
	}
	if result.RecoveryResolutionProof {
		if result.ResolutionID != ledger.LastResolutionID ||
			result.ResolutionAction != ledger.LastResolutionAction ||
			result.PlanDigest != ledger.PlanDigest ||
			result.ServerConfigurationDigest != ledger.ServerConfigurationDigest ||
			result.WorldRelativePath != ledger.WorldRelativePath || result.RecoveryRequired {
			return fail("restore_ledger_resolution_proof_invalid", nil)
		}
		if result.Phase == "completed" {
			if result.VerifiedWorldState != "selected" || result.RolledBack {
				return fail("restore_ledger_resolution_selected_proof_invalid", nil)
			}
		} else if result.Phase == "rolled_back" {
			if (result.VerifiedWorldState != "pre_restore" && result.VerifiedWorldState != "original_absent") ||
				!result.RolledBack {
				return fail("restore_ledger_resolution_rollback_proof_invalid", nil)
			}
		} else {
			return fail("restore_ledger_resolution_phase_invalid", nil)
		}
	} else if result.ResolutionID != "" && result.ResolutionID != ledger.LastResolutionID {
		return fail("restore_ledger_resolution_result_invalid", nil)
	}

	switch {
	case result.RecoveryRequired:
		if ledger.Phase != "recovery_required" || result.Phase != "recovery_required" || result.ErrorCode == "" {
			return fail("restore_ledger_recovery_result_invalid", nil)
		}
	case result.RolledBack:
		if ledger.Phase != "rolled_back" || result.Phase != "rolled_back" || result.ErrorCode == "" ||
			result.PreRestoreBackup == nil {
			return fail("restore_ledger_rollback_result_invalid", nil)
		}
	case result.ErrorCode == "":
		if ledger.Phase != "completed" || result.Phase != "completed" ||
			result.InstalledManifestDigest != ledger.BackupManifestDigest || result.PreRestoreBackup == nil {
			return fail("restore_ledger_success_result_invalid", nil)
		}
	default:
		if destructivePhase(ledger.Phase) {
			return fail("restore_ledger_failure_result_invalid", nil)
		}
	}
	return nil
}

func (store *Store) saveLedger(ledger *RestoreLedger) error {
	if err := store.validateLedger(ledger); err != nil {
		return err
	}
	ledger.UpdatedAt = time.Now().UTC()
	data, err := json.MarshalIndent(ledger, "", "  ")
	if err != nil {
		return fail("restore_ledger_encode_failed", err)
	}
	data = append(data, '\n')
	if int64(len(data)) > maxLedgerBytes {
		return fail("restore_ledger_size_exceeded", nil)
	}
	path := filepath.Join(store.ledgerRoot, ledger.PlanID+".json")
	file, err := os.CreateTemp(store.ledgerRoot, "."+ledger.PlanID+".next-*")
	if err != nil {
		return fail("restore_ledger_write_failed", err)
	}
	temporary := file.Name()
	if _, err = file.Write(data); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		_ = os.Remove(temporary)
		return fail("restore_ledger_write_failed", err)
	}
	if err := replaceFileAtomic(temporary, path); err != nil {
		return fail("restore_ledger_replace_failed", err)
	}
	store.ledgerMu.Lock()
	copyValue := *ledger
	store.ledgers[ledger.PlanID] = &copyValue
	store.ledgerMu.Unlock()
	return nil
}

func (store *Store) ledger(planID string) *RestoreLedger {
	store.ledgerMu.RLock()
	defer store.ledgerMu.RUnlock()
	value := store.ledgers[planID]
	if value == nil {
		return nil
	}
	copyValue := *value
	return &copyValue
}

func (store *Store) RecoveryRequired() bool {
	store.ledgerMu.RLock()
	defer store.ledgerMu.RUnlock()
	for _, ledger := range store.ledgers {
		if ledgerRequiresRecovery(ledger) {
			return true
		}
	}
	return false
}

func (store *Store) BlocksServer(serverID string) bool {
	store.ledgerMu.RLock()
	defer store.ledgerMu.RUnlock()
	for _, ledger := range store.ledgers {
		if ledger.ServerID == serverID && ledgerRequiresRecovery(ledger) {
			return true
		}
	}
	return false
}

func ledgerRequiresRecovery(ledger *RestoreLedger) bool {
	if ledger.Result == nil || ledger.Result.RecoveryRequired {
		return true
	}
	return ledger.LastResolutionID != "" && !ledger.Result.RecoveryResolutionProof
}

func (store *Store) newLedger(request RestoreRequest, livePath string) *RestoreLedger {
	parent := filepath.Dir(livePath)
	prefix := ".mcweb-world-restore-" + request.PlanID + "-"
	now := time.Now().UTC()
	return &RestoreLedger{
		Version:                   ledgerVersion,
		PlanID:                    request.PlanID,
		PlanDigest:                request.PlanDigest,
		OperationDeliveryID:       request.OperationDeliveryID,
		OperationPayloadDigest:    request.OperationPayloadDigest,
		ServerID:                  request.ServerID,
		NodeID:                    request.NodeID,
		BackupID:                  request.BackupID,
		BackupManifestDigest:      request.BackupManifestDigest,
		PreRestoreBackupID:        request.PreRestoreBackupID,
		ServerConfigurationDigest: request.ServerConfigurationDigest,
		LocalConfigurationDigest:  configurationDigest(request.WorkingDirectory, request.WorldRelativePath),
		WorkingDirectory:          request.WorkingDirectory,
		WorldRelativePath:         request.WorldRelativePath,
		LivePath:                  livePath,
		StagingPath:               filepath.Join(parent, prefix+"staging"),
		RollbackPath:              filepath.Join(parent, prefix+"rollback"),
		FailedReplacementPath:     filepath.Join(parent, prefix+"failed"),
		Phase:                     "accepted",
		CreatedAt:                 now,
		UpdatedAt:                 now,
	}
}

func (ledger *RestoreLedger) matches(request RestoreRequest) bool {
	return ledger.PlanID == request.PlanID && ledger.PlanDigest == request.PlanDigest &&
		ledger.OperationDeliveryID == request.OperationDeliveryID &&
		ledger.OperationPayloadDigest == request.OperationPayloadDigest &&
		ledger.ServerID == request.ServerID && ledger.NodeID == request.NodeID &&
		ledger.BackupID == request.BackupID && ledger.BackupManifestDigest == request.BackupManifestDigest &&
		ledger.PreRestoreBackupID == request.PreRestoreBackupID &&
		ledger.ServerConfigurationDigest == request.ServerConfigurationDigest &&
		ledger.LocalConfigurationDigest == configurationDigest(request.WorkingDirectory, request.WorldRelativePath) &&
		ledger.WorkingDirectory == request.WorkingDirectory && ledger.WorldRelativePath == request.WorldRelativePath
}

func (ledger *RestoreLedger) setPhase(phase string) {
	if _, ok := restorePhases[phase]; !ok {
		panic(fmt.Sprintf("unknown restore phase %q", phase))
	}
	ledger.Phase = phase
}
