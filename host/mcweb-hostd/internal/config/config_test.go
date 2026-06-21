package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/mcweb/mcweb-hostd/internal/config"
)

func TestSetAdminPassword(t *testing.T) {
	cfg := config.Default()
	if err := config.SetAdminPassword(cfg, "admin", "secret123"); err != nil {
		t.Fatal(err)
	}
	if !cfg.Initialized {
		t.Fatal("expected initialized")
	}
	if !config.CheckAdminPassword(cfg, "admin", "secret123") {
		t.Fatal("password check failed")
	}
}

func TestSaveLoad(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "hostd.yml")
	cfg := config.Default()
	_ = config.SetAdminPassword(cfg, "admin", "secret123")
	_ = cfg.EnsureSecretKey()
	if err := config.Save(path, cfg); err != nil {
		t.Fatal(err)
	}
	loaded, err := config.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.AdminUsername != "admin" {
		t.Fatalf("got %q", loaded.AdminUsername)
	}
}

func TestDefaultPathEnv(t *testing.T) {
	t.Setenv("MCWEB_HOSTD_CONFIG", filepath.Join(t.TempDir(), "custom.yml"))
	if config.ConfigPath() == config.DefaultPath {
		t.Fatal("expected custom path from env")
	}
	_ = os.Unsetenv("MCWEB_HOSTD_CONFIG")
}
