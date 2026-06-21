package ops

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/mcweb/mcweb-hostd/internal/config"
	"github.com/mcweb/mcweb-hostd/internal/mcweb"
)

type Job struct {
	ID        string
	Kind      string
	Status    string // running | success | failed
	StartedAt time.Time
	EndedAt   time.Time
	Log       []string
	mu        sync.Mutex
}

func (j *Job) Append(line string) {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.Log = append(j.Log, line)
}

func (j *Job) LogText() string {
	j.mu.Lock()
	defer j.mu.Unlock()
	return strings.Join(j.Log, "\n")
}

type JobManager struct {
	mu   sync.RWMutex
	jobs map[string]*Job
	dir  string
}

func NewJobManager(dir string) *JobManager {
	_ = os.MkdirAll(dir, 0o755)
	return &JobManager{jobs: make(map[string]*Job), dir: dir}
}

func (m *JobManager) Start(kind string, fn func(*Job) error) *Job {
	id := fmt.Sprintf("%d", time.Now().UnixNano())
	job := &Job{ID: id, Kind: kind, Status: "running", StartedAt: time.Now()}
	m.mu.Lock()
	m.jobs[id] = job
	m.mu.Unlock()
	go func() {
		err := fn(job)
		job.EndedAt = time.Now()
		if err != nil {
			job.Status = "failed"
			job.Append("ERROR: " + err.Error())
		} else {
			job.Status = "success"
		}
		_ = os.WriteFile(filepath.Join(m.dir, id+".log"), []byte(job.LogText()), 0o644)
	}()
	return job
}

func (m *JobManager) Get(id string) (*Job, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	j, ok := m.jobs[id]
	return j, ok
}

func (m *JobManager) Recent(limit int) []*Job {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]*Job, 0, len(m.jobs))
	for _, j := range m.jobs {
		out = append(out, j)
	}
	if len(out) > limit {
		out = out[len(out)-limit:]
	}
	return out
}

type Lifecycle struct {
	Cfg *config.Config
	Jobs *JobManager
}

func NewLifecycle(cfg *config.Config, jobs *JobManager) *Lifecycle {
	return &Lifecycle{Cfg: cfg, Jobs: jobs}
}

func (l *Lifecycle) nativeUnits(all bool) []string {
	if all {
		return []string{"mcweb-web", "mcweb-worker"}
	}
	return []string{"mcweb-web", "mcweb-worker"}
}

func (l *Lifecycle) Start(web, worker, all, docker bool) *Job {
	return l.Jobs.Start("start", func(j *Job) error {
		if docker || l.Cfg.DeployMode == "docker" {
			return runCompose(j, l.Cfg.ComposeDir, "start")
		}
		units := l.nativeUnits(all)
		if web && !worker {
			units = []string{"mcweb-web"}
		} else if worker && !web {
			units = []string{"mcweb-worker"}
		}
		return systemctl(j, "start", units...)
	})
}

func (l *Lifecycle) Stop(web, worker, all, docker bool) *Job {
	return l.Jobs.Start("stop", func(j *Job) error {
		if docker || l.Cfg.DeployMode == "docker" {
			return runCompose(j, l.Cfg.ComposeDir, "stop")
		}
		units := l.nativeUnits(all)
		if web && !worker {
			units = []string{"mcweb-web"}
		} else if worker && !web {
			units = []string{"mcweb-worker"}
		}
		return systemctl(j, "stop", units...)
	})
}

func (l *Lifecycle) Restart(web, worker, all, docker bool) *Job {
	return l.Jobs.Start("restart", func(j *Job) error {
		if docker || l.Cfg.DeployMode == "docker" {
			return runCompose(j, l.Cfg.ComposeDir, "restart")
		}
		units := l.nativeUnits(all)
		if web && !worker {
			units = []string{"mcweb-web"}
		} else if worker && !web {
			units = []string{"mcweb-worker"}
		}
		return systemctl(j, "restart", units...)
	})
}

func (l *Lifecycle) Check() *Job {
	return l.Jobs.Start("check", func(j *Job) error {
		paths := mcweb.ResolvePaths(l.Cfg.McwebRoot, l.Cfg.McwebEnvFile)
		if paths.Installed() {
			out, err := exec.Command(paths.DoctorBin()).CombinedOutput()
			j.Append(string(out))
			if err != nil {
				j.Append(err.Error())
			}
		}
		h := mcweb.CheckHealth(l.Cfg.HealthURL)
		j.Append(fmt.Sprintf("health/live: ok=%v body=%s", h.Live, h.LiveBody))
		j.Append(fmt.Sprintf("health/ready: ok=%v body=%s", h.Ready, h.ReadyBody))
		if l.Cfg.DeployMode == "docker" {
			out, _ := exec.Command("docker", "compose", "-f", l.Cfg.ComposeDir+"/docker-compose.yml", "ps").CombinedOutput()
			j.Append(string(out))
		}
		return nil
	})
}

func (l *Lifecycle) Update(version string) *Job {
	return l.Jobs.Start("update", func(j *Job) error {
		if l.Cfg.DeployMode == "docker" {
			if err := runCompose(j, l.Cfg.ComposeDir, "pull"); err != nil {
				return err
			}
			return runCompose(j, l.Cfg.ComposeDir, "up", "-d")
		}
		paths := mcweb.ResolvePaths(l.Cfg.McwebRoot, l.Cfg.McwebEnvFile)
		if version != "" {
			j.Append("Downloading release " + version)
			if err := downloadRelease(j, l.Cfg, version); err != nil {
				return err
			}
		}
		out, err := exec.Command(paths.UpdateBin()).CombinedOutput()
		j.Append(string(out))
		return err
	})
}

func (l *Lifecycle) Logs(web, worker, follow bool) string {
	if l.Cfg.DeployMode == "docker" {
		args := []string{"compose", "-f", l.Cfg.ComposeDir + "/docker-compose.yml", "logs", "--tail=100"}
		if follow {
			args = append(args, "-f")
		}
		out, _ := exec.Command("docker", args...).CombinedOutput()
		return string(out)
	}
	unit := "mcweb-web"
	if worker && !web {
		unit = "mcweb-worker"
	}
	args := []string{"-u", unit, "-n", "100", "--no-pager"}
	if follow {
		args = []string{"-u", unit, "-f"}
	}
	out, _ := exec.Command("journalctl", args...).CombinedOutput()
	return string(out)
}

func systemctl(j *Job, action string, units ...string) error {
	args := append([]string{action}, units...)
	cmd := exec.Command("systemctl", args...)
	out, err := cmd.CombinedOutput()
	j.Append("$ systemctl " + strings.Join(args, " "))
	j.Append(string(out))
	return err
}

func runCompose(j *Job, dir, action string, extra ...string) error {
	args := append([]string{"compose", "-f", dir + "/docker-compose.yml", action}, extra...)
	cmd := exec.Command("docker", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	j.Append("$ docker " + strings.Join(args, " "))
	j.Append(string(out))
	return err
}

func downloadRelease(j *Job, cfg *config.Config, version string) error {
	url := strings.TrimRight(cfg.ReleaseURL, "/") + "/mcweb-" + version + ".tar.gz"
	dest := filepath.Join("/tmp", "mcweb-"+version+".tar.gz")
	j.Append("curl " + url)
	cmd := exec.Command("curl", "-fsSL", "-o", dest, url)
	out, err := cmd.CombinedOutput()
	j.Append(string(out))
	if err != nil {
		return err
	}
	script := filepath.Join(cfg.McwebRoot, "quick-install.sh")
	if _, err := os.Stat(script); err != nil {
		script = "/opt/mcweb/current/quick-install.sh"
	}
	cmd = exec.Command("bash", script, dest)
	out, err = cmd.CombinedOutput()
	j.Append(string(out))
	return err
}

func (l *Lifecycle) InstallNative(fresh bool, version string) *Job {
	return l.Jobs.Start("install-native", func(j *Job) error {
		if fresh {
			installScript := filepath.Join(l.Cfg.McwebRoot, "..", "..", "bin", "install")
			if _, err := os.Stat(installScript); err != nil {
				installScript = "/opt/mcweb/current/bin/install"
			}
			j.Append("Running fresh install via bin/install")
			out, err := exec.Command("bash", installScript).CombinedOutput()
			j.Append(string(out))
			if err != nil {
				return err
			}
		} else if version != "" {
			if err := downloadRelease(j, l.Cfg, version); err != nil {
				return err
			}
		}
		return systemctl(j, "enable", "--now", "mcweb-web", "mcweb-worker")
	})
}

func (l *Lifecycle) InstallDocker(pull bool) *Job {
	return l.Jobs.Start("install-docker", func(j *Job) error {
		if pull {
			if err := runCompose(j, l.Cfg.ComposeDir, "pull"); err != nil {
				return err
			}
		}
		return runCompose(j, l.Cfg.ComposeDir, "up", "-d")
	})
}

func (l *Lifecycle) Finalize(input mcweb.FinalizeInput) *Job {
	return l.Jobs.Start("finalize", func(j *Job) error {
		paths := mcweb.ResolvePaths(l.Cfg.McwebRoot, l.Cfg.McwebEnvFile)
		result, err := mcweb.RunFinalize(paths, input)
		j.Append(result.Message)
		if result.Error != "" {
			j.Append(result.Error)
		}
		if err != nil {
			return err
		}
		if !result.Success {
			return fmt.Errorf("finalize failed")
		}
		return config.WriteInstalledViaHostdMarker()
	})
}
