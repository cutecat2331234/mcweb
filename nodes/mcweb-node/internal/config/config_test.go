package config

import (
	"path/filepath"
	"testing"
)

func TestSaveAndLoadPairedConfiguration(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mcweb-node.yml")
	expected := &Config{
		RailsURL:   "https://mcweb.example",
		NodeID:     "node-1",
		NodeSecret: "secret-value",
	}
	if err := Save(path, expected); err != nil {
		t.Fatalf("Save: %v", err)
	}
	loaded, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if loaded.NodeID != expected.NodeID || loaded.NodeSecret != expected.NodeSecret {
		t.Fatalf("unexpected config: %+v", loaded)
	}
	if loaded.ProxyListen == "" || loaded.PollInterval == 0 || loaded.SpoolDir == "" {
		t.Fatalf("defaults missing: %+v", loaded)
	}
	if loaded.WorldBackupRoot == "" || loaded.WorldRestoreLimits.MaxArchiveBytes <= 0 ||
		loaded.WorldRestoreLimits.MaxExpansionRatio <= 0 {
		t.Fatalf("world safety defaults missing: %+v", loaded)
	}
}
