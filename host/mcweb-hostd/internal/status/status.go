package status

import (
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/mcweb/mcweb-hostd/internal/config"
	"github.com/mcweb/mcweb-hostd/internal/mcweb"
)

type UnitStatus struct {
	Name   string
	Active bool
	State  string
	Since  string
}

type Report struct {
	Timestamp       time.Time
	DeployMode      string
	McwebVersion    string
	McwebInstalled  bool
	InstalledViaHostd bool
	Health          mcweb.HealthResult
	Units           []UnitStatus
	DiskFree        string
	DoctorOutput    string
}

func Collect(cfg *config.Config) Report {
	paths := mcweb.ResolvePaths(cfg.McwebRoot, cfg.McwebEnvFile)
	report := Report{
		Timestamp:      time.Now(),
		DeployMode:     cfg.DeployMode,
		McwebVersion:   paths.Version(),
		McwebInstalled: paths.Installed(),
		Health:         mcweb.CheckHealth(cfg.HealthURL),
	}
	if _, err := os.Stat(config.InstalledViaHostdMarker()); err == nil {
		report.InstalledViaHostd = true
	}
	report.Units = collectUnits(cfg)
	report.DiskFree = diskFree(cfg.McwebRoot)
	if paths.Installed() {
		report.DoctorOutput = runDoctor(paths)
	}
	return report
}

func collectUnits(cfg *config.Config) []UnitStatus {
	names := []string{"mcweb-web", "mcweb-worker", "mcweb-hostd"}
	if cfg.DeployMode == "docker" {
		return dockerPS(cfg.ComposeDir)
	}
	var units []UnitStatus
	for _, name := range names {
		units = append(units, unitStatus(name))
	}
	return units
}

func unitStatus(name string) UnitStatus {
	u := UnitStatus{Name: name}
	out, err := exec.Command("systemctl", "is-active", name).Output()
	if err == nil && strings.TrimSpace(string(out)) == "active" {
		u.Active = true
		u.State = "active"
	} else {
		u.State = strings.TrimSpace(string(out))
		if u.State == "" {
			u.State = "inactive"
		}
	}
	if since, err := exec.Command("systemctl", "show", name, "--property=ActiveEnterTimestamp", "--value").Output(); err == nil {
		u.Since = strings.TrimSpace(string(since))
	}
	return u
}

func dockerPS(composeDir string) []UnitStatus {
	out, err := exec.Command("docker", "compose", "-f", composeDir+"/docker-compose.yml", "ps", "--format", "{{.Name}}\t{{.State}}").Output()
	if err != nil {
		return []UnitStatus{{Name: "docker", State: "unavailable"}}
	}
	var units []UnitStatus
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		u := UnitStatus{Name: parts[0]}
		if len(parts) > 1 {
			u.State = parts[1]
			u.Active = strings.Contains(strings.ToLower(parts[1]), "running")
		}
		units = append(units, u)
	}
	return units
}

func diskFree(path string) string {
	out, err := exec.Command("df", "-h", path).Output()
	if err != nil {
		return ""
	}
	lines := strings.Split(string(out), "\n")
	if len(lines) > 1 {
		return strings.TrimSpace(lines[1])
	}
	return strings.TrimSpace(string(out))
}

func runDoctor(paths mcweb.Paths) string {
	out, err := exec.Command(paths.DoctorBin()).CombinedOutput()
	if err != nil {
		return string(out) + "\n" + err.Error()
	}
	return string(out)
}
