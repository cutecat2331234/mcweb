package mcweb

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	DefaultRoot    = "/opt/mcweb/current"
	DefaultEnvFile = "/etc/mcweb/mcweb.env"
)

type Paths struct {
	Root    string
	EnvFile string
}

func ResolvePaths(root, envFile string) Paths {
	if root == "" {
		root = DefaultRoot
	}
	if envFile == "" {
		envFile = DefaultEnvFile
	}
	return Paths{Root: root, EnvFile: envFile}
}

func (p Paths) Version() string {
	data, err := os.ReadFile(filepath.Join(p.Root, "VERSION"))
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(data))
}

func (p Paths) DoctorBin() string {
	return filepath.Join(p.Root, "bin", "doctor")
}

func (p Paths) UpdateBin() string {
	return filepath.Join(p.Root, "bin", "update")
}

func (p Paths) FinalizeBin() string {
	return filepath.Join(p.Root, "bin", "hostd-finalize")
}

func (p Paths) Installed() bool {
	if _, err := os.Stat(p.Root); err != nil {
		return false
	}
	_, err := os.Stat(p.FinalizeBin())
	return err == nil || fileExists(filepath.Join(p.Root, "bin", "rails"))
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

type HealthResult struct {
	Live  bool
	Ready bool
	LiveBody  string
	ReadyBody string
}

func CheckHealth(baseURL string) HealthResult {
	result := HealthResult{}
	client := &http.Client{Timeout: 5 * time.Second}
	if resp, err := client.Get(strings.TrimRight(baseURL, "/") + "/health/live"); err == nil {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		result.Live = resp.StatusCode == http.StatusOK
		result.LiveBody = string(body)
	}
	if resp, err := client.Get(strings.TrimRight(baseURL, "/") + "/health/ready"); err == nil {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		result.Ready = resp.StatusCode == http.StatusOK
		result.ReadyBody = string(body)
	}
	return result
}

type FinalizeInput struct {
	Database struct {
		Host               string `json:"host"`
		Port               int    `json:"port"`
		Username           string `json:"username"`
		Password           string `json:"password"`
		DevelopmentDatabase string `json:"development_database"`
		TestDatabase       string `json:"test_database"`
		ProductionDatabase string `json:"production_database"`
	} `json:"database"`
	Site struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	} `json:"site"`
	Admin struct {
		Email       string `json:"email"`
		Username    string `json:"username"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
	} `json:"admin"`
}

type FinalizeOutput struct {
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
	Message string `json:"message,omitempty"`
}

func RunFinalize(p Paths, input FinalizeInput) (FinalizeOutput, error) {
	data, err := json.Marshal(input)
	if err != nil {
		return FinalizeOutput{}, err
	}
	tmp, err := os.CreateTemp("", "hostd-finalize-*.json")
	if err != nil {
		return FinalizeOutput{}, err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		return FinalizeOutput{}, err
	}
	tmp.Close()

	cmd := exec.Command(p.FinalizeBin(), "--input", tmp.Name())
	cmd.Dir = p.Root
	cmd.Env = append(os.Environ(), "BUNDLE_GEMFILE="+filepath.Join(p.Root, "Gemfile"))
	if data, err := os.ReadFile(p.EnvFile); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			cmd.Env = append(cmd.Env, line)
		}
	}
	out, err := cmd.CombinedOutput()
	var result FinalizeOutput
	if json.Unmarshal(out, &result) != nil {
		if err != nil {
			return FinalizeOutput{}, fmt.Errorf("%w: %s", err, string(out))
		}
		result.Success = true
		result.Message = strings.TrimSpace(string(out))
	}
	if err != nil && !result.Success {
		return result, fmt.Errorf("%w: %s", err, string(out))
	}
	return result, nil
}
