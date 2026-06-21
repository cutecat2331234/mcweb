package ops

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/mcweb/mcweb-hostd/internal/config"
	"github.com/mcweb/mcweb-hostd/internal/mcweb"
)

const (
	PluginsDir = "/var/lib/mcweb/plugins"
	NodeBinary = "/usr/local/bin/mcweb-node"
)

type ExtendedOps struct {
	Cfg  *config.Config
	Jobs *JobManager
}

func NewExtendedOps(cfg *config.Config, jobs *JobManager) *ExtendedOps {
	return &ExtendedOps{Cfg: cfg, Jobs: jobs}
}

func (e *ExtendedOps) Backup() *Job {
	return e.Jobs.Start("backup", func(j *Job) error {
		paths := mcweb.ResolvePaths(e.Cfg.McwebRoot, e.Cfg.McwebEnvFile)
		backupBin := filepath.Join(paths.Root, "bin", "backup")
		if _, err := os.Stat(backupBin); err != nil {
			j.Append("bin/backup not found; see docs/HOSTD.md for manual backup")
			return nil
		}
		cmd := exec.Command(backupBin)
		out, err := cmd.CombinedOutput()
		j.Append(string(out))
		return err
	})
}

func (e *ExtendedOps) Restore(archive string) *Job {
	return e.Jobs.Start("restore", func(j *Job) error {
		paths := mcweb.ResolvePaths(e.Cfg.McwebRoot, e.Cfg.McwebEnvFile)
		restoreBin := filepath.Join(paths.Root, "bin", "restore")
		if _, err := os.Stat(restoreBin); err != nil {
			return fmt.Errorf("bin/restore not found")
		}
		cmd := exec.Command(restoreBin, archive)
		out, err := cmd.CombinedOutput()
		j.Append(string(out))
		return err
	})
}

func (e *ExtendedOps) InstallNode() *Job {
	return e.Jobs.Start("install-node", func(j *Job) error {
		_ = os.MkdirAll(filepath.Dir(NodeBinary), 0o755)
		j.Append("Place mcweb-node binary at " + NodeBinary)
		j.Append("Configure /etc/mcweb/node.yml from config/templates/mcweb-node.service")
		out, err := exec.Command("systemctl", "enable", "--now", "mcweb-node").CombinedOutput()
		j.Append(string(out))
		if err != nil {
			j.Append("systemctl mcweb-node: " + err.Error())
		}
		return nil
	})
}

func (e *ExtendedOps) EnsurePluginsDir() error {
	return os.MkdirAll(PluginsDir, 0o755)
}

func (e *ExtendedOps) InstallPluginPlaceholder(name string) *Job {
	return e.Jobs.Start("install-plugin", func(j *Job) error {
		if err := e.EnsurePluginsDir(); err != nil {
			return err
		}
		dest := filepath.Join(PluginsDir, name)
		j.Append("Plugin directory ready: " + dest)
		j.Append("Rails plugin boot loader is not yet implemented; restart mcweb-web after manual install")
		return nil
	})
}
