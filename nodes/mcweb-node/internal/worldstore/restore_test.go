package worldstore

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestManagedBackupRestoreRoundTripIsStoppedGatedAndIdempotent(t *testing.T) {
	store, workingDirectory, livePath := newTestWorldStore(t)
	writeWorldFile(t, livePath, "level.dat", "known-good")

	stoppedChecks := 0
	checkStopped := func(context.Context) error {
		stoppedChecks++
		return nil
	}
	backup, err := store.CreateBackup(context.Background(), BackupRequest{
		BackupID:          "backup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "manual",
		RequestDigest:     strings.Repeat("a", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      checkStopped,
	})
	if err != nil {
		t.Fatalf("CreateBackup: %v", err)
	}
	writeWorldFile(t, livePath, "level.dat", "mutated-live-state")

	request := restoreRequest(t, workingDirectory, backup.ManifestDigest, checkStopped)
	result, err := store.Restore(context.Background(), request)
	if err != nil {
		t.Fatalf("Restore: %v result=%+v", err, result)
	}
	if result.Phase != "completed" || result.RolledBack || result.RecoveryRequired ||
		result.InstalledManifestDigest != backup.ManifestDigest || result.PreRestoreBackup == nil {
		t.Fatalf("unexpected restore result: %+v", result)
	}
	if got := readWorldFile(t, livePath, "level.dat"); got != "known-good" {
		t.Fatalf("installed content=%q", got)
	}
	if result.PreRestoreBackup.Purpose != "pre_restore" || result.PreRestoreBackup.ManifestDigest == "" {
		t.Fatalf("pre-restore snapshot missing: %+v", result.PreRestoreBackup)
	}
	if backup.RequestDigest != strings.Repeat("a", 64) ||
		result.PreRestoreBackup.RequestDigest != request.PlanDigest {
		t.Fatalf("managed backup request binding missing: backup=%+v pre=%+v", backup, result.PreRestoreBackup)
	}

	replayed, replayErr := store.Restore(context.Background(), request)
	if replayErr != nil || replayed.CompletedAt != result.CompletedAt || replayed.Phase != "completed" {
		t.Fatalf("idempotent replay changed result: result=%+v err=%v", replayed, replayErr)
	}
	if stoppedChecks < 5 {
		t.Fatalf("expected repeated stopped-process gates, got %d", stoppedChecks)
	}
	if store.RecoveryRequired() || store.BlocksServer("server_test_01") {
		t.Fatal("completed restore must not leave the node start-blocked")
	}
}

func TestRestoreOfAbsentWorldPreservesAbsence(t *testing.T) {
	store, workingDirectory, livePath := newTestWorldStore(t)
	if err := os.Remove(livePath); err != nil {
		t.Fatal(err)
	}
	checkStopped := func(context.Context) error { return nil }
	backup, err := store.CreateBackup(context.Background(), BackupRequest{
		BackupID:          "backup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "manual",
		RequestDigest:     strings.Repeat("a", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      checkStopped,
	})
	if err != nil || backup.SourceWorldState != "absent" {
		t.Fatalf("CreateBackup: backup=%+v err=%v", backup, err)
	}
	writeWorldFile(t, livePath, "level.dat", "world-to-remove")

	result, err := store.Restore(
		context.Background(),
		restoreRequest(t, workingDirectory, backup.ManifestDigest, checkStopped),
	)
	if err != nil || result == nil || result.Phase != "completed" {
		t.Fatalf("Restore absent world: result=%+v err=%v", result, err)
	}
	if _, statErr := os.Lstat(livePath); !os.IsNotExist(statErr) {
		t.Fatalf("absent backup installed an unexpected live directory: %v", statErr)
	}
}

func TestInterruptedCutoverCompletesFromDurableLedgerWhenInstalledTreeIsProven(t *testing.T) {
	store, workingDirectory, livePath := newTestWorldStore(t)
	checkStopped := func(context.Context) error { return nil }
	writeWorldFile(t, livePath, "level.dat", "selected-world")
	selected, err := store.CreateBackup(context.Background(), BackupRequest{
		BackupID:          "backup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "manual",
		RequestDigest:     strings.Repeat("a", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      checkStopped,
	})
	if err != nil {
		t.Fatal(err)
	}
	writeWorldFile(t, livePath, "level.dat", "previous-world")
	preRestore, err := store.CreateBackup(context.Background(), BackupRequest{
		BackupID:          "prebackup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "pre_restore",
		RequestDigest:     strings.Repeat("b", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      checkStopped,
	})
	if err != nil {
		t.Fatal(err)
	}

	request := restoreRequest(t, workingDirectory, selected.ManifestDigest, checkStopped)
	ledger := store.newLedger(request, livePath)
	ledger.PreRestoreManifestDigest = preRestore.ManifestDigest
	ledger.LiveWasAbsent = false
	if err := renameDirectory(livePath, ledger.RollbackPath); err != nil {
		t.Fatal(err)
	}
	writeWorldFile(t, livePath, "level.dat", "selected-world")
	ledger.setPhase("replacement_installed")
	if err := store.saveLedger(ledger); err != nil {
		t.Fatal(err)
	}

	reopened, err := New(store.backupRoot, store.ledgerRoot, "node_test_01", DefaultLimits())
	if err != nil {
		t.Fatalf("reopen store: %v", err)
	}
	if !reopened.RecoveryRequired() || !reopened.BlocksServer("server_test_01") {
		t.Fatal("unfinished destructive ledger must block server start")
	}
	result, err := reopened.Restore(context.Background(), request)
	if err != nil || result == nil || result.Phase != "completed" {
		t.Fatalf("resume restore: result=%+v err=%v", result, err)
	}
	if _, err := os.Lstat(ledger.RollbackPath); !os.IsNotExist(err) {
		t.Fatalf("rollback tree was not safely removed: %v", err)
	}
	if got := readWorldFile(t, livePath, "level.dat"); got != "selected-world" {
		t.Fatalf("resumed installed content=%q", got)
	}
}

func TestInterruptedCutoverDoesNotMutateWorldWhenStoppedCheckFails(t *testing.T) {
	store, workingDirectory, livePath := newTestWorldStore(t)
	stopped := func(context.Context) error { return nil }
	writeWorldFile(t, livePath, "level.dat", "selected-world")
	selected, err := store.CreateBackup(context.Background(), BackupRequest{
		BackupID:          "backup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "manual",
		RequestDigest:     strings.Repeat("a", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      stopped,
	})
	if err != nil {
		t.Fatal(err)
	}
	writeWorldFile(t, livePath, "level.dat", "previous-world")
	preRestore, err := store.CreateBackup(context.Background(), BackupRequest{
		BackupID:          "prebackup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "pre_restore",
		RequestDigest:     strings.Repeat("c", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      stopped,
	})
	if err != nil {
		t.Fatal(err)
	}

	running := func(context.Context) error { return fail("process_running", nil) }
	request := restoreRequest(t, workingDirectory, selected.ManifestDigest, running)
	ledger := store.newLedger(request, livePath)
	ledger.PreRestoreManifestDigest = preRestore.ManifestDigest
	ledger.LiveWasAbsent = false
	if err := renameDirectory(livePath, ledger.RollbackPath); err != nil {
		t.Fatal(err)
	}
	ledger.setPhase("live_preserved")
	if err := store.saveLedger(ledger); err != nil {
		t.Fatal(err)
	}

	result, restoreErr := store.Restore(context.Background(), request)
	if Code(restoreErr) != "server_process_not_stopped" || result == nil || !result.RecoveryRequired {
		t.Fatalf("running resume was not blocked: result=%+v err=%v", result, restoreErr)
	}
	if _, statErr := os.Lstat(livePath); !os.IsNotExist(statErr) {
		t.Fatalf("running resume unexpectedly recreated live world: %v", statErr)
	}
	if got := readWorldFile(t, ledger.RollbackPath, "level.dat"); got != "previous-world" {
		t.Fatalf("running resume changed rollback tree: %q", got)
	}
	if _, backupErr := store.CreateBackup(context.Background(), BackupRequest{}); Code(backupErr) != "world_restore_recovery_required" {
		t.Fatalf("recovery state accepted another world operation: %v", backupErr)
	}
}

func TestRecoveryResolutionRequiresDurableNodeProofBeforeUnblocking(t *testing.T) {
	store, workingDirectory, livePath := newTestWorldStore(t)
	stopped := func(context.Context) error { return nil }
	writeWorldFile(t, livePath, "level.dat", "selected-world")
	selected, err := store.CreateBackup(context.Background(), BackupRequest{
		BackupID:          "backup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "manual",
		RequestDigest:     strings.Repeat("a", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      stopped,
	})
	if err != nil {
		t.Fatal(err)
	}
	writeWorldFile(t, livePath, "level.dat", "previous-world")
	preRestore, err := store.CreateBackup(context.Background(), BackupRequest{
		BackupID:          "prebackup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "pre_restore",
		RequestDigest:     strings.Repeat("c", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      stopped,
	})
	if err != nil {
		t.Fatal(err)
	}

	restore := restoreRequest(t, workingDirectory, selected.ManifestDigest, stopped)
	ledger := store.newLedger(restore, livePath)
	ledger.PreRestoreManifestDigest = preRestore.ManifestDigest
	if err := renameDirectory(livePath, ledger.RollbackPath); err != nil {
		t.Fatal(err)
	}
	writeWorldFile(t, livePath, "level.dat", "selected-world")
	if _, markErr := store.markRecoveryRequired(
		ledger,
		preRestore,
		fail("restore_interrupted_cutover", nil),
	); markErr == nil {
		t.Fatal("expected recovery-required marker error")
	}
	if !store.RecoveryRequired() || !store.BlocksServer("server_test_01") {
		t.Fatal("recovery ledger did not block world operations")
	}

	request := recoveryResolutionRequest(restore, preRestore.ManifestDigest, stopped)
	result, err := store.ResolveRecovery(context.Background(), request)
	if err != nil {
		t.Fatalf("ResolveRecovery: result=%+v err=%v", result, err)
	}
	if result == nil || !result.RecoveryResolutionProof || result.ResolutionID != request.ResolutionID ||
		result.VerifiedWorldState != "selected" || result.Phase != "completed" {
		t.Fatalf("invalid recovery proof: %+v", result)
	}
	if store.RecoveryRequired() || store.BlocksServer("server_test_01") {
		t.Fatal("durably proven recovery result remained blocked")
	}
	replayed, replayErr := store.ResolveRecovery(context.Background(), request)
	if replayErr != nil || replayed.CompletedAt != result.CompletedAt {
		t.Fatalf("recovery proof replay was not idempotent: result=%+v err=%v", replayed, replayErr)
	}
}

func TestManagedBackupIdempotencyBindsRequestDigest(t *testing.T) {
	store, workingDirectory, livePath := newTestWorldStore(t)
	writeWorldFile(t, livePath, "level.dat", "known-good")
	request := BackupRequest{
		BackupID:          "backup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "manual",
		RequestDigest:     strings.Repeat("a", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      func(context.Context) error { return nil },
	}
	if _, err := store.CreateBackup(context.Background(), request); err != nil {
		t.Fatal(err)
	}
	request.RequestDigest = strings.Repeat("b", 64)
	if _, err := store.CreateBackup(context.Background(), request); Code(err) != "backup_idempotency_conflict" {
		t.Fatalf("request digest conflict was accepted: %v", err)
	}
}

func TestArchiveScannerRejectsTrailingDataAfterDigestRebinding(t *testing.T) {
	store, workingDirectory, livePath := newTestWorldStore(t)
	writeWorldFile(t, livePath, "level.dat", "known-good")
	checkStopped := func(context.Context) error { return nil }
	backup, err := store.CreateBackup(context.Background(), BackupRequest{
		BackupID:          "backup_test_01",
		ServerID:          "server_test_01",
		NodeID:            "node_test_01",
		Purpose:           "manual",
		RequestDigest:     strings.Repeat("a", 64),
		WorkingDirectory:  workingDirectory,
		WorldRelativePath: "world",
		CheckStopped:      checkStopped,
	})
	if err != nil {
		t.Fatal(err)
	}
	manifest, err := store.loadBackup("server_test_01", "backup_test_01", backup.ManifestDigest)
	if err != nil {
		t.Fatal(err)
	}
	archivePath := store.archivePath("server_test_01", "backup_test_01")
	file, err := os.OpenFile(archivePath, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = file.Write([]byte("trailing-data")); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		t.Fatal(err)
	}
	manifest.ArchiveSHA256, manifest.ArchiveBytes, err = digestFile(archivePath, DefaultLimits().MaxArchiveBytes)
	if err != nil {
		t.Fatal(err)
	}
	err = scanOrExtractArchive(manifest, archivePath, "", DefaultLimits())
	if Code(err) != "archive_concatenated_or_trailing_data" {
		t.Fatalf("expected trailing-data rejection, got %v", err)
	}
}

func TestArchiveScannerBoundsCompressedMetadataExpansion(t *testing.T) {
	archivePath := filepath.Join(t.TempDir(), "metadata-bomb.tar.gz")
	file, err := os.OpenFile(archivePath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	gzipWriter := gzip.NewWriter(file)
	tarWriter := tar.NewWriter(gzipWriter)
	// Keep each GNU metadata record below archive/tar's per-record limit while
	// making their cumulative decompressed size exceed the scanner's allowance.
	const metadataFieldBytes = 600 * 1024
	header := &tar.Header{
		Name:     strings.Repeat("n", metadataFieldBytes),
		Linkname: strings.Repeat("l", metadataFieldBytes),
		Typeflag: tar.TypeSymlink,
		Mode:     0o600,
		Format:   tar.FormatGNU,
	}
	if err = tarWriter.WriteHeader(header); err == nil {
		err = tarWriter.Close()
	}
	if err == nil {
		err = gzipWriter.Close()
	}
	if err == nil {
		err = file.Close()
	} else {
		_ = file.Close()
	}
	if err != nil {
		t.Fatal(err)
	}

	archiveDigest, archiveBytes, err := digestFile(archivePath, DefaultLimits().MaxArchiveBytes)
	if err != nil {
		t.Fatal(err)
	}
	manifest := &Manifest{
		ArchiveSHA256:     archiveDigest,
		ArchiveBytes:      archiveBytes,
		UncompressedBytes: 0,
		EntryCount:        1,
		DirectoryCount:    0,
		SourceWorldState:  "present",
		Entries: []ManifestEntry{{
			Path: "level.dat", Type: "file", Size: 0,
			SHA256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		}},
	}
	if err := scanOrExtractArchive(manifest, archivePath, "", DefaultLimits()); Code(err) != "archive_decompression_quota_exceeded" {
		t.Fatalf("metadata expansion was not bounded: %v", err)
	}
}

func newTestWorldStore(t *testing.T) (*Store, string, string) {
	t.Helper()
	root := t.TempDir()
	workingDirectory := filepath.Join(root, "server")
	livePath := filepath.Join(workingDirectory, "world")
	if err := os.MkdirAll(livePath, 0o700); err != nil {
		t.Fatal(err)
	}
	store, err := New(
		filepath.Join(root, "backups"),
		filepath.Join(root, "ledgers"),
		"node_test_01",
		DefaultLimits(),
	)
	if err != nil {
		t.Fatal(err)
	}
	return store, workingDirectory, livePath
}

func restoreRequest(
	t *testing.T,
	workingDirectory string,
	backupManifestDigest string,
	checkStopped CheckStopped,
) RestoreRequest {
	t.Helper()
	processConfig := map[string]interface{}{"status": "./status.sh"}
	configurationDigest, err := ServerConfigurationDigest(
		"server_test_01",
		"node_test_01",
		workingDirectory,
		"world",
		"script",
		processConfig,
	)
	if err != nil {
		t.Fatal(err)
	}
	return RestoreRequest{
		PlanID:                    "restore_plan_01",
		PlanDigest:                strings.Repeat("c", 64),
		OperationDeliveryID:       "delivery_test_01",
		OperationPayloadDigest:    strings.Repeat("d", 64),
		ServerID:                  "server_test_01",
		NodeID:                    "node_test_01",
		BackupID:                  "backup_test_01",
		BackupManifestDigest:      backupManifestDigest,
		PreRestoreBackupID:        "prebackup_test_01",
		ServerConfigurationDigest: configurationDigest,
		ProcessDriver:             "script",
		ProcessConfig:             processConfig,
		WorkingDirectory:          workingDirectory,
		WorldRelativePath:         "world",
		CheckStopped:              checkStopped,
	}
}

func recoveryResolutionRequest(
	restore RestoreRequest,
	preRestoreManifestDigest string,
	checkStopped CheckStopped,
) RecoveryResolutionRequest {
	return RecoveryResolutionRequest{
		ResolutionID:              "resolution_test_01",
		ResolutionAction:          "reconcile",
		ReasonDigest:              strings.Repeat("e", 64),
		OperationDeliveryID:       "resolution_delivery_01",
		OperationPayloadDigest:    strings.Repeat("f", 64),
		RecoveryCapabilityDigest:  strings.Repeat("9", 64),
		PlanID:                    restore.PlanID,
		PlanDigest:                restore.PlanDigest,
		ServerID:                  restore.ServerID,
		NodeID:                    restore.NodeID,
		BackupID:                  restore.BackupID,
		BackupManifestDigest:      restore.BackupManifestDigest,
		PreRestoreBackupID:        restore.PreRestoreBackupID,
		PreRestoreManifestDigest:  preRestoreManifestDigest,
		ServerConfigurationDigest: restore.ServerConfigurationDigest,
		ProcessDriver:             restore.ProcessDriver,
		ProcessConfig:             restore.ProcessConfig,
		WorkingDirectory:          restore.WorkingDirectory,
		WorldRelativePath:         restore.WorldRelativePath,
		CheckStopped:              checkStopped,
	}
}

func writeWorldFile(t *testing.T, livePath, relative, content string) {
	t.Helper()
	path := filepath.Join(livePath, relative)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func readWorldFile(t *testing.T, livePath, relative string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(livePath, relative))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
