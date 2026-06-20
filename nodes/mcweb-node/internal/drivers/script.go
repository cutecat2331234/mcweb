package drivers

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type ScriptDriver struct{}

func (d *ScriptDriver) Start(ctx context.Context, cfg ProcessConfig) error {
	script := cfgStr(cfg.Config, "start")
	if script == "" {
		return fmt.Errorf("script start not configured")
	}
	return runScript(ctx, cfg.WorkingDirectory, script)
}

func (d *ScriptDriver) Stop(ctx context.Context, cfg ProcessConfig, timeout time.Duration) error {
	script := cfgStr(cfg.Config, "stop")
	if script == "" {
		return fmt.Errorf("script stop not configured")
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	return runScript(ctx, cfg.WorkingDirectory, script)
}

func (d *ScriptDriver) Restart(ctx context.Context, cfg ProcessConfig) error {
	if err := d.Stop(ctx, cfg, 60*time.Second); err != nil {
		return err
	}
	return d.Start(ctx, cfg)
}

func (d *ScriptDriver) Status(ctx context.Context, cfg ProcessConfig) (ProcessState, error) {
	script := cfgStr(cfg.Config, "status")
	if script == "" {
		return StateError, fmt.Errorf("script status not configured")
	}
	err := runScript(ctx, cfg.WorkingDirectory, script)
	if err != nil {
		return StateStopped, nil
	}
	return StateRunning, nil
}

func runScript(ctx context.Context, dir, script string) error {
	cmd := exec.CommandContext(ctx, "sh", "-c", script)
	if dir != "" {
		cmd.Dir = dir
	}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func cfgStr(m map[string]interface{}, key string) string {
	if m == nil {
		return ""
	}
	v, ok := m[key]
	if !ok {
		return ""
	}
	return strings.TrimSpace(fmt.Sprint(v))
}

func absPath(dir, p string) string {
	if filepath.IsAbs(p) {
		return p
	}
	if dir == "" {
		return p
	}
	return filepath.Join(dir, p)
}
