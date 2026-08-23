package drivers

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type NssmDriver struct{}

func (d *NssmDriver) Start(ctx context.Context, cfg ProcessConfig) error {
	service := cfgStr(cfg.Config, "service")
	if service == "" {
		return fmt.Errorf("nssm service not configured")
	}
	return exec.CommandContext(ctx, nssmBin(cfg), "start", service).Run()
}

func (d *NssmDriver) Stop(ctx context.Context, cfg ProcessConfig, timeout time.Duration) error {
	service := cfgStr(cfg.Config, "service")
	if service == "" {
		return fmt.Errorf("nssm service not configured")
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	return exec.CommandContext(ctx, nssmBin(cfg), "stop", service).Run()
}

func (d *NssmDriver) Restart(ctx context.Context, cfg ProcessConfig) error {
	service := cfgStr(cfg.Config, "service")
	if service == "" {
		return fmt.Errorf("nssm service not configured")
	}
	return exec.CommandContext(ctx, nssmBin(cfg), "restart", service).Run()
}

func (d *NssmDriver) Status(ctx context.Context, cfg ProcessConfig) (ProcessState, error) {
	service := cfgStr(cfg.Config, "service")
	if service == "" {
		return StateError, fmt.Errorf("nssm service not configured")
	}
	out, err := exec.CommandContext(ctx, nssmBin(cfg), "status", service).CombinedOutput()
	if err != nil {
		return StateError, fmt.Errorf("nssm status is indeterminate: %w", err)
	}
	text := strings.ToLower(strings.TrimSpace(string(out)))
	switch {
	case strings.Contains(text, "service_running"):
		return StateRunning, nil
	case strings.Contains(text, "service_start_pending"):
		return StateStarting, nil
	case strings.Contains(text, "service_stop_pending"), strings.Contains(text, "service_paused"):
		return StateStopping, nil
	case strings.Contains(text, "service_stopped"):
		return StateStopped, nil
	default:
		return StateError, fmt.Errorf("nssm returned an unknown service state")
	}
}

func nssmBin(cfg ProcessConfig) string {
	if bin := cfgStr(cfg.Config, "nssm_path"); bin != "" {
		return bin
	}
	return "nssm"
}
