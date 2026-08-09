package config

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	RailsURL     string        `yaml:"rails_url"`
	NodeID       string        `yaml:"node_id"`
	NodeSecret   string        `yaml:"node_secret"`
	ProxyListen  string        `yaml:"proxy_listen"`
	PollInterval time.Duration `yaml:"poll_interval"`
	SpoolDir     string        `yaml:"spool_dir"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	cfg.ApplyDefaults()
	return &cfg, nil
}

func (cfg *Config) ApplyDefaults() {
	if cfg.ProxyListen == "" {
		cfg.ProxyListen = "127.0.0.1:9876"
	}
	if cfg.PollInterval == 0 {
		cfg.PollInterval = 10 * time.Second
	}
	if cfg.SpoolDir == "" {
		cfg.SpoolDir = "spool"
	}
}

func Save(path string, cfg *Config) error {
	if path == "" || cfg == nil {
		return fmt.Errorf("config path and value are required")
	}
	cfg.ApplyDefaults()
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	tmp := path + ".next"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		if removeErr := os.Remove(path); removeErr != nil && !os.IsNotExist(removeErr) {
			_ = os.Remove(tmp)
			return removeErr
		}
		if retryErr := os.Rename(tmp, path); retryErr != nil {
			return retryErr
		}
	}
	return nil
}
