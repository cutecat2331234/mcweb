package executor

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/mcweb/mcweb-node/internal/drivers"
	"github.com/mcweb/mcweb-node/internal/metrics"
	"github.com/mcweb/mcweb-node/internal/worldstore"
)

type Executor struct {
	worldStore          *worldstore.Store
	worldSafetyRequired bool
}

func New() *Executor {
	return NewWithUnavailableWorldSafety()
}

func NewWithWorldStore(store *worldstore.Store) *Executor {
	return &Executor{worldStore: store, worldSafetyRequired: true}
}

func NewWithUnavailableWorldSafety() *Executor {
	return &Executor{worldSafetyRequired: true}
}

func (e *Executor) Run(ctx context.Context, task map[string]interface{}) map[string]interface{} {
	taskType, _ := task["task_type"].(string)
	payload, _ := task["payload"].(map[string]interface{})

	switch taskType {
	case "start_instance", "stop_instance", "restart_instance":
		return e.lifecycle(ctx, taskType, task, payload)
	case "exec_command":
		return e.execCommand(ctx, payload)
	case "collect_metrics":
		return e.collectMetrics(ctx, payload)
	case "tail_logs":
		return e.tailLogs(ctx, payload)
	case "backup_world", "restore_world":
		return failCode("legacy_world_operation_retired")
	case "world_backup_create":
		return e.createManagedWorldBackup(ctx, payload)
	case "world_restore_execute":
		return e.executeManagedWorldRestore(ctx, payload)
	case "world_restore_reconcile":
		return e.reconcileManagedWorldRestore(ctx, payload)
	case "sync_files":
		return e.syncFiles(ctx, payload)
	default:
		return fail(fmt.Sprintf("unknown task type: %s", taskType))
	}
}

func (e *Executor) lifecycle(ctx context.Context, taskType string, task, payload map[string]interface{}) map[string]interface{} {
	if taskType == "start_instance" || taskType == "restart_instance" {
		if e.worldSafetyRequired && (e.worldStore == nil || e.worldStore.BlocksServer(strVal(payload, "server_id"))) {
			return failCode("world_restore_recovery_required")
		}
	}
	driverName := strVal(payload, "process_driver")
	configMap := mapVal(payload, "process_config")
	wd := strVal(payload, "working_directory")
	cfg := drivers.ProcessConfig{
		Driver:           driverName,
		Config:           configMap,
		WorkingDirectory: wd,
	}
	drv := drivers.For(driverName)

	var err error
	switch taskType {
	case "start_instance":
		err = drv.Start(ctx, cfg)
	case "stop_instance":
		timeout := 60 * time.Second
		if t, ok := payload["timeout_seconds"].(float64); ok && t > 0 {
			timeout = time.Duration(t) * time.Second
		}
		err = drv.Stop(ctx, cfg, timeout)
	case "restart_instance":
		err = drv.Restart(ctx, cfg)
	}

	if err != nil {
		return fail(err.Error())
	}
	state, _ := drv.Status(ctx, cfg)
	return map[string]interface{}{
		"success":       true,
		"status":        "completed",
		"message":       taskType + " ok",
		"process_state": string(state),
	}
}

func (e *Executor) execCommand(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	command, _ := payload["command"].(string)
	if command == "" {
		return fail("command required")
	}
	cwd, _ := payload["cwd"].(string)
	timeout := 60 * time.Second
	if t, ok := payload["timeout"].(float64); ok && t > 0 {
		timeout = time.Duration(t) * time.Second
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "sh", "-c", command)
	if cwd != "" {
		cmd.Dir = cwd
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	result := map[string]interface{}{
		"stdout": stdout.String(),
		"stderr": stderr.String(),
	}
	if err != nil {
		result["success"] = false
		result["status"] = "failed"
		result["error"] = err.Error()
		return result
	}
	result["success"] = true
	result["status"] = "completed"
	result["message"] = "command executed"
	return result
}

func (e *Executor) collectMetrics(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	host := metrics.CollectHost()
	metricsPayload := map[string]interface{}{
		"host": host,
	}

	driverName := strVal(payload, "process_driver")
	if driverName != "" {
		cfg := drivers.ProcessConfig{
			Driver:           driverName,
			Config:           mapVal(payload, "process_config"),
			WorkingDirectory: strVal(payload, "working_directory"),
		}
		if state, err := drivers.For(driverName).Status(ctx, cfg); err == nil {
			metricsPayload["instance"] = map[string]interface{}{
				"process_state": string(state),
				"server_id":     strVal(payload, "server_id"),
			}
		}
	}

	result := map[string]interface{}{
		"success": true,
		"status":  "completed",
		"message": "metrics collected",
		"metrics": metricsPayload,
	}
	if inst, ok := metricsPayload["instance"].(map[string]interface{}); ok {
		if ps, ok := inst["process_state"].(string); ok {
			result["process_state"] = ps
		}
	}
	return result
}

func (e *Executor) tailLogs(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	path, _ := payload["path"].(string)
	if path == "" {
		return fail("path required")
	}
	lines := 100
	if n, ok := payload["lines"].(float64); ok && n > 0 {
		lines = int(n)
	}
	out, err := exec.CommandContext(ctx, "tail", "-n", fmt.Sprintf("%d", lines), path).CombinedOutput()
	if err != nil {
		return fail(err.Error())
	}
	return map[string]interface{}{
		"success": true,
		"status":  "completed",
		"output":  string(out),
	}
}

func (e *Executor) createManagedWorldBackup(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	if e.worldStore == nil {
		return failCode("managed_world_store_unavailable")
	}
	if strVal(payload, "safety_profile") != worldstore.SafetyProfile || numberVal(payload, "protocol_version") != 2 {
		return failCode("managed_world_protocol_invalid")
	}
	manifest, err := e.worldStore.CreateBackup(ctx, worldstore.BackupRequest{
		BackupID:          strVal(payload, "backup_id"),
		ServerID:          strVal(payload, "server_id"),
		NodeID:            strVal(payload, "node_id"),
		Purpose:           strVal(payload, "purpose"),
		RequestDigest:     strVal(payload, "request_digest"),
		WorkingDirectory:  strVal(payload, "working_directory"),
		WorldRelativePath: strVal(payload, "world_relative_path"),
		CheckStopped:      stoppedCheck(payload),
	})
	if err != nil {
		return worldOperationFailure(err, nil, "backup")
	}
	return map[string]interface{}{
		"success": true,
		"status":  "completed",
		"message": "managed world backup created",
		"backup":  manifest,
	}
}

func (e *Executor) executeManagedWorldRestore(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	if e.worldStore == nil {
		return failCode("managed_world_store_unavailable")
	}
	if strVal(payload, "safety_profile") != worldstore.SafetyProfile || numberVal(payload, "protocol_version") != 2 ||
		strVal(payload, "expected_process_state") != "stopped" {
		return failCode("managed_world_protocol_invalid")
	}
	result, err := e.worldStore.Restore(ctx, worldstore.RestoreRequest{
		PlanID:                    strVal(payload, "plan_id"),
		PlanDigest:                strVal(payload, "plan_digest"),
		OperationDeliveryID:       strVal(payload, "operation_delivery_id"),
		OperationPayloadDigest:    strVal(payload, "operation_payload_digest"),
		ServerID:                  strVal(payload, "server_id"),
		NodeID:                    strVal(payload, "node_id"),
		BackupID:                  strVal(payload, "backup_id"),
		BackupManifestDigest:      strVal(payload, "backup_manifest_digest"),
		PreRestoreBackupID:        strVal(payload, "pre_restore_backup_id"),
		ServerConfigurationDigest: strVal(payload, "server_configuration_digest"),
		ProcessDriver:             strVal(payload, "process_driver"),
		ProcessConfig:             mapVal(payload, "process_config"),
		WorkingDirectory:          strVal(payload, "working_directory"),
		WorldRelativePath:         strVal(payload, "world_relative_path"),
		CheckStopped:              stoppedCheck(payload),
	})
	if err != nil {
		return worldOperationFailure(err, result, "restore")
	}
	return map[string]interface{}{
		"success": true,
		"status":  "completed",
		"message": "managed world restore completed",
		"restore": result,
	}
}

func (e *Executor) reconcileManagedWorldRestore(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	if e.worldStore == nil {
		return failCode("managed_world_store_unavailable")
	}
	if strVal(payload, "safety_profile") != worldstore.SafetyProfile || numberVal(payload, "protocol_version") != 2 ||
		strVal(payload, "expected_process_state") != "stopped" {
		return failCode("managed_world_protocol_invalid")
	}
	result, err := e.worldStore.ResolveRecovery(ctx, worldstore.RecoveryResolutionRequest{
		ResolutionID:              strVal(payload, "resolution_id"),
		ResolutionAction:          strVal(payload, "resolution_action"),
		ReasonDigest:              strVal(payload, "reason_digest"),
		OperationDeliveryID:       strVal(payload, "operation_delivery_id"),
		OperationPayloadDigest:    strVal(payload, "operation_payload_digest"),
		RecoveryCapabilityDigest:  strVal(payload, "recovery_capability_digest"),
		PlanID:                    strVal(payload, "plan_id"),
		PlanDigest:                strVal(payload, "plan_digest"),
		ServerID:                  strVal(payload, "server_id"),
		NodeID:                    strVal(payload, "node_id"),
		BackupID:                  strVal(payload, "backup_id"),
		BackupManifestDigest:      strVal(payload, "backup_manifest_digest"),
		PreRestoreBackupID:        strVal(payload, "pre_restore_backup_id"),
		PreRestoreManifestDigest:  strVal(payload, "pre_restore_manifest_digest"),
		ServerConfigurationDigest: strVal(payload, "server_configuration_digest"),
		ProcessDriver:             strVal(payload, "process_driver"),
		ProcessConfig:             mapVal(payload, "process_config"),
		WorkingDirectory:          strVal(payload, "working_directory"),
		WorldRelativePath:         strVal(payload, "world_relative_path"),
		CheckStopped:              stoppedCheck(payload),
	})
	if err != nil {
		return worldOperationFailure(err, result, "recovery_resolution")
	}
	return map[string]interface{}{
		"success":             true,
		"status":              "completed",
		"message":             "managed world restore recovery resolved",
		"recovery_resolution": result,
	}
}

func stoppedCheck(payload map[string]interface{}) worldstore.CheckStopped {
	config := drivers.ProcessConfig{
		Driver:           strVal(payload, "process_driver"),
		Config:           mapVal(payload, "process_config"),
		WorkingDirectory: strVal(payload, "working_directory"),
	}
	return func(ctx context.Context) error {
		state, err := drivers.For(config.Driver).Status(ctx, config)
		if err != nil {
			return err
		}
		if state != drivers.StateStopped {
			return fmt.Errorf("process state is %s", state)
		}
		return nil
	}
}

func worldOperationFailure(err error, result interface{}, resultKey string) map[string]interface{} {
	code := worldstore.Code(err)
	response := failCode(code)
	if result != nil {
		response[resultKey] = result
	}
	return response
}

func (e *Executor) syncFiles(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	url := strVal(payload, "url")
	dest, err := syncDestination(payload)
	if err != nil {
		return fail(err.Error())
	}
	if url == "" || dest == "" {
		return fail("url and destination required")
	}
	if err := validateSyncURL(url); err != nil {
		return fail(err.Error())
	}
	if err := os.MkdirAll(filepathDir(dest), 0o755); err != nil {
		return fail(err.Error())
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fail(err.Error())
	}
	client := &http.Client{
		Timeout: 10 * time.Minute,
		CheckRedirect: func(request *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return fmt.Errorf("too many sync redirects")
			}
			return validateSyncURL(request.URL.String())
		},
	}
	response, err := client.Do(request)
	if err != nil {
		return fail(err.Error())
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fail(fmt.Sprintf("sync download returned HTTP %d", response.StatusCode))
	}
	maxBytes := syncMaxBytes(payload)
	if response.ContentLength > maxBytes {
		return fail("sync download exceeds maximum size")
	}

	tmp, err := os.CreateTemp(filepathDir(dest), ".mcweb-sync-*")
	if err != nil {
		return fail(err.Error())
	}
	tmpPath := tmp.Name()
	keepTemp := true
	defer func() {
		_ = tmp.Close()
		if keepTemp {
			_ = os.Remove(tmpPath)
		}
	}()

	hasher := sha256.New()
	written, err := io.Copy(io.MultiWriter(tmp, hasher), io.LimitReader(response.Body, maxBytes+1))
	if err != nil {
		return fail(err.Error())
	}
	if written > maxBytes {
		return fail("sync download exceeds maximum size")
	}
	if err := tmp.Sync(); err != nil {
		return fail(err.Error())
	}
	if err := tmp.Close(); err != nil {
		return fail(err.Error())
	}

	actualDigest := hex.EncodeToString(hasher.Sum(nil))
	expectedDigest := strings.ToLower(strings.TrimSpace(strVal(payload, "sha256")))
	if expectedDigest != "" {
		if _, err := hex.DecodeString(expectedDigest); err != nil || len(expectedDigest) != sha256.Size*2 {
			return fail("invalid sha256 digest")
		}
		if actualDigest != expectedDigest {
			return fail("downloaded file sha256 mismatch")
		}
	}
	if err := replaceFile(tmpPath, dest); err != nil {
		return fail(err.Error())
	}
	keepTemp = false
	return map[string]interface{}{
		"success":          true,
		"status":           "completed",
		"message":          "file synced",
		"destination":      dest,
		"sha256":           actualDigest,
		"applied_revision": strVal(payload, "revision"),
	}
}

func syncMaxBytes(payload map[string]interface{}) int64 {
	const defaultMaxBytes int64 = 2 * 1024 * 1024 * 1024
	if value, ok := payload["max_bytes"].(float64); ok && value > 0 && value <= float64(defaultMaxBytes) {
		return int64(value)
	}
	return defaultMaxBytes
}

func syncDestination(payload map[string]interface{}) (string, error) {
	if dest := strVal(payload, "destination"); dest != "" {
		return dest, nil
	}
	root := strVal(payload, "working_directory")
	relative := strVal(payload, "relative_path")
	if root == "" || relative == "" {
		return "", fmt.Errorf("working_directory and relative_path required")
	}
	if filepath.IsAbs(relative) {
		return "", fmt.Errorf("relative_path must be relative")
	}
	cleanRelative := filepath.Clean(relative)
	if cleanRelative == ".." || strings.HasPrefix(cleanRelative, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("relative_path escapes working_directory")
	}

	rootAbsolute, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	destination := filepath.Join(rootAbsolute, cleanRelative)
	withinRoot, err := filepath.Rel(rootAbsolute, destination)
	if err != nil || withinRoot == ".." || strings.HasPrefix(withinRoot, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("relative_path escapes working_directory")
	}
	return destination, nil
}

func replaceFile(source, destination string) error {
	if err := os.Rename(source, destination); err == nil {
		return nil
	}
	if _, err := os.Stat(destination); err != nil {
		return fmt.Errorf("replace destination: %w", err)
	}

	backup := destination + ".mcweb-previous"
	_ = os.Remove(backup)
	if err := os.Rename(destination, backup); err != nil {
		return fmt.Errorf("preserve previous destination: %w", err)
	}
	if err := os.Rename(source, destination); err != nil {
		_ = os.Rename(backup, destination)
		return fmt.Errorf("replace destination: %w", err)
	}
	_ = os.Remove(backup)
	return nil
}

func fail(msg string) map[string]interface{} {
	return map[string]interface{}{
		"success": false,
		"status":  "failed",
		"error":   msg,
	}
}

func failCode(code string) map[string]interface{} {
	return map[string]interface{}{
		"success":    false,
		"status":     "failed",
		"error":      code,
		"error_code": code,
	}
}

func strVal(m map[string]interface{}, key string) string {
	if m == nil {
		return ""
	}
	v, ok := m[key]
	if !ok || v == nil {
		return ""
	}
	return fmt.Sprint(v)
}

func mapVal(m map[string]interface{}, key string) map[string]interface{} {
	if m == nil {
		return map[string]interface{}{}
	}
	v, ok := m[key].(map[string]interface{})
	if !ok {
		return map[string]interface{}{}
	}
	return v
}

func numberVal(m map[string]interface{}, key string) int {
	if m == nil {
		return 0
	}
	switch value := m[key].(type) {
	case float64:
		return int(value)
	case int:
		return value
	case json.Number:
		integer, _ := value.Int64()
		return int(integer)
	default:
		return 0
	}
}

func filepathJoin(elem ...string) string {
	return filepath.Join(elem...)
}

func filepathDir(path string) string {
	return filepath.Dir(path)
}

func filepathBase(path string) string {
	return filepath.Base(path)
}
