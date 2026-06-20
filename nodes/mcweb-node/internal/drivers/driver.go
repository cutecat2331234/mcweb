package drivers

import (
	"context"
	"time"
)

type ProcessState string

const (
	StateStopped  ProcessState = "stopped"
	StateStarting ProcessState = "starting"
	StateRunning  ProcessState = "running"
	StateStopping ProcessState = "stopping"
	StateError    ProcessState = "error"
)

type ProcessConfig struct {
	Driver            string
	Config            map[string]interface{}
	WorkingDirectory  string
}

type Driver interface {
	Start(ctx context.Context, cfg ProcessConfig) error
	Stop(ctx context.Context, cfg ProcessConfig, timeout time.Duration) error
	Restart(ctx context.Context, cfg ProcessConfig) error
	Status(ctx context.Context, cfg ProcessConfig) (ProcessState, error)
}

func For(driver string) Driver {
	switch driver {
	case "systemd":
		return &SystemdDriver{}
	case "docker":
		return &DockerDriver{}
	case "script":
		return &ScriptDriver{}
	default:
		return &ScriptDriver{}
	}
}
