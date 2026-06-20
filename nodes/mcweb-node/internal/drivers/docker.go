package drivers

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type DockerDriver struct{}

func (d *DockerDriver) Start(ctx context.Context, cfg ProcessConfig) error {
	return d.runCompose(ctx, cfg, "start")
}

func (d *DockerDriver) Stop(ctx context.Context, cfg ProcessConfig, timeout time.Duration) error {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	return d.runCompose(ctx, cfg, "stop")
}

func (d *DockerDriver) Restart(ctx context.Context, cfg ProcessConfig) error {
	return d.runCompose(ctx, cfg, "restart")
}

func (d *DockerDriver) Status(ctx context.Context, cfg ProcessConfig) (ProcessState, error) {
	service := cfgStr(cfg.Config, "service")
	if service == "" {
		return StateError, fmt.Errorf("docker service not configured")
	}
	composeFile := cfgStr(cfg.Config, "compose_file")
	args := composeArgs(composeFile, "ps", "--status", "running", service)
	cmd := exec.CommandContext(ctx, "docker", args...)
	out, err := cmd.Output()
	if err != nil {
		return StateStopped, nil
	}
	if strings.Contains(string(out), service) {
		return StateRunning, nil
	}
	return StateStopped, nil
}

func (d *DockerDriver) runCompose(ctx context.Context, cfg ProcessConfig, action string) error {
	service := cfgStr(cfg.Config, "service")
	if service == "" {
		return fmt.Errorf("docker service not configured")
	}
	composeFile := cfgStr(cfg.Config, "compose_file")
	args := composeArgs(composeFile, action, service)
	return exec.CommandContext(ctx, "docker", args...).Run()
}

func composeArgs(composeFile string, parts ...string) []string {
	args := []string{"compose"}
	if composeFile != "" {
		args = append(args, "-f", composeFile)
	}
	return append(args, parts...)
}
