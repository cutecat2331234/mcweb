package executor

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/mcweb/mcweb-node/internal/drivers"
	"github.com/mcweb/mcweb-node/internal/metrics"
)

type Executor struct{}

func New() *Executor {
	return &Executor{}
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
	case "backup_world":
		return e.backupWorld(ctx, payload)
	case "restore_world":
		return e.restoreWorld(ctx, payload)
	case "sync_files":
		return e.syncFiles(ctx, payload)
	default:
		return fail(fmt.Sprintf("unknown task type: %s", taskType))
	}
}

func (e *Executor) lifecycle(ctx context.Context, taskType string, task, payload map[string]interface{}) map[string]interface{} {
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

func (e *Executor) backupWorld(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	cwd := strVal(payload, "working_directory")
	source := strVal(payload, "source")
	if source == "" {
		source = "world"
	}
	dest := strVal(payload, "destination")
	if dest == "" {
		return fail("destination required")
	}
	srcPath := source
	if cwd != "" && !strings.HasPrefix(source, "/") {
		srcPath = filepathJoin(cwd, source)
	}
	if err := os.MkdirAll(filepathDir(dest), 0o755); err != nil {
		return fail(err.Error())
	}
	out, err := exec.CommandContext(ctx, "tar", "-czf", dest, "-C", filepathDir(srcPath), filepathBase(srcPath)).CombinedOutput()
	if err != nil {
		return fail(string(out) + ": " + err.Error())
	}
	return map[string]interface{}{
		"success":     true,
		"status":      "completed",
		"message":     "backup created",
		"destination": dest,
	}
}

func (e *Executor) restoreWorld(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	cwd := strVal(payload, "working_directory")
	archive := strVal(payload, "archive")
	if archive == "" {
		return fail("archive required")
	}
	target := strVal(payload, "target")
	if target == "" {
		target = "world"
	}
	destDir := target
	if cwd != "" && !strings.HasPrefix(target, "/") {
		destDir = filepathJoin(cwd, target)
	}
	if err := os.MkdirAll(filepathDir(destDir), 0o755); err != nil {
		return fail(err.Error())
	}
	out, err := exec.CommandContext(ctx, "tar", "-xzf", archive, "-C", destDir).CombinedOutput()
	if err != nil {
		return fail(string(out) + ": " + err.Error())
	}
	return map[string]interface{}{
		"success": true,
		"status":  "completed",
		"message": "world restored",
	}
}

func (e *Executor) syncFiles(ctx context.Context, payload map[string]interface{}) map[string]interface{} {
	url := strVal(payload, "url")
	dest := strVal(payload, "destination")
	if url == "" || dest == "" {
		return fail("url and destination required")
	}
	if err := validateSyncURL(url); err != nil {
		return fail(err.Error())
	}
	if err := os.MkdirAll(filepathDir(dest), 0o755); err != nil {
		return fail(err.Error())
	}
	out, err := exec.CommandContext(ctx, "curl", "-fsSL", "-o", dest, url).CombinedOutput()
	if err != nil {
		return fail(string(out) + ": " + err.Error())
	}
	return map[string]interface{}{
		"success":     true,
		"status":      "completed",
		"message":     "file synced",
		"destination": dest,
	}
}

func fail(msg string) map[string]interface{} {
	return map[string]interface{}{
		"success": false,
		"status":  "failed",
		"error":   msg,
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

func filepathJoin(elem ...string) string {
	return filepath.Join(elem...)
}

func filepathDir(path string) string {
	return filepath.Dir(path)
}

func filepathBase(path string) string {
	return filepath.Base(path)
}
