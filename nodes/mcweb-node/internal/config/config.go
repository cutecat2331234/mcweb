package config

import (
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	RailsURL     string        `yaml:"rails_url"`
	NodeID       string        `yaml:"node_id"`
	NodeSecret   string        `yaml:"node_secret"`
	ProxyListen  string        `yaml:"proxy_listen"`
	PollInterval time.Duration `yaml:"poll_interval"`
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
	if cfg.ProxyListen == "" {
		cfg.ProxyListen = "127.0.0.1:9876"
	}
	if cfg.PollInterval == 0 {
		cfg.PollInterval = 10 * time.Second
	}
	return &cfg, nil
}
