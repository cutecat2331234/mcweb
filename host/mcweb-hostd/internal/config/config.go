package config

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/crypto/bcrypt"
	"gopkg.in/yaml.v3"
)

const DefaultPath = "/etc/mcweb/hostd.yml"

type Config struct {
	Listen           string `yaml:"listen"`
	SecretKey        string `yaml:"secret_key"`
	AdminUsername    string `yaml:"admin_username"`
	AdminPasswordHash string `yaml:"admin_password_hash"`
	McwebRoot        string `yaml:"mcweb_root"`
	McwebEnvFile     string `yaml:"mcweb_env_file"`
	ComposeDir       string `yaml:"compose_dir"`
	DeployMode       string `yaml:"deploy_mode"` // native | docker
	ReleaseURL       string `yaml:"release_url"`
	HealthURL        string `yaml:"health_url"`
	JobLogDir        string `yaml:"job_log_dir"`
	Initialized      bool   `yaml:"initialized"`
}

func Default() *Config {
	return &Config{
		Listen:       ":8787",
		McwebRoot:    "/opt/mcweb/current",
		McwebEnvFile: "/etc/mcweb/mcweb.env",
		ComposeDir:   "/opt/mcweb/docker",
		DeployMode:   "native",
		HealthURL:    "http://127.0.0.1:3000",
		JobLogDir:    "/var/log/mcweb/hostd/jobs",
	}
}

func Load(path string) (*Config, error) {
	cfg := Default()
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return nil, err
	}
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

func Save(path string, cfg *Config) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

func (c *Config) EnsureSecretKey() error {
	if c.SecretKey != "" {
		return nil
	}
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return err
	}
	c.SecretKey = hex.EncodeToString(buf)
	return nil
}

func SetAdminPassword(cfg *Config, username, password string) error {
	if username == "" || password == "" {
		return errors.New("username and password required")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	cfg.AdminUsername = username
	cfg.AdminPasswordHash = string(hash)
	cfg.Initialized = true
	return nil
}

func CheckAdminPassword(cfg *Config, username, password string) bool {
	if cfg.AdminUsername == "" || cfg.AdminPasswordHash == "" {
		return false
	}
	if username != cfg.AdminUsername {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(cfg.AdminPasswordHash), []byte(password)) == nil
}

func ResolvePath(path string) string {
	if path == "" {
		return DefaultPath
	}
	return path
}

func InstalledViaHostdMarker() string {
	return "/etc/mcweb/installed_via_hostd"
}

func WriteInstalledViaHostdMarker() error {
	return os.WriteFile(InstalledViaHostdMarker(), []byte("1\n"), 0o644)
}

func ConfigPath() string {
	if p := os.Getenv("MCWEB_HOSTD_CONFIG"); p != "" {
		return p
	}
	return DefaultPath
}

func PrintInitHint(path string) {
	fmt.Printf("Hostd initialized. Config: %s\n", path)
	fmt.Println("Run: mcweb-hostd serve")
}
