package drivers

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type SystemdDriver struct{}

func (d *SystemdDriver) Start(ctx context.Context, cfg ProcessConfig) error {
	unit := cfgStr(cfg.Config, "unit")
	if unit == "" {
		return fmt.Errorf("systemd unit not configured")
	}
	return exec.CommandContext(ctx, "systemctl", "start", unit).Run()
}

func (d *SystemdDriver) Stop(ctx context.Context, cfg ProcessConfig, timeout time.Duration) error {
	unit := cfgStr(cfg.Config, "unit")
	if unit == "" {
		return fmt.Errorf("systemd unit not configured")
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	return exec.CommandContext(ctx, "systemctl", "stop", unit).Run()
}

func (d *SystemdDriver) Restart(ctx context.Context, cfg ProcessConfig) error {
	unit := cfgStr(cfg.Config, "unit")
	if unit == "" {
		return fmt.Errorf("systemd unit not configured")
	}
	return exec.CommandContext(ctx, "systemctl", "restart", unit).Run()
}

func (d *SystemdDriver) Status(ctx context.Context, cfg ProcessConfig) (ProcessState, error) {
	unit := cfgStr(cfg.Config, "unit")
	if unit == "" {
		return StateError, fmt.Errorf("systemd unit not configured")
	}
	out, err := exec.CommandContext(ctx, "systemctl", "is-active", unit).Output()
	if err != nil {
		return StateStopped, nil
	}
	if strings.TrimSpace(string(out)) == "active" {
		return StateRunning, nil
	}
	return StateStopped, nil
}
