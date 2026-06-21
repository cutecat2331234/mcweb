package spool

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSpoolEnqueueListRemove(t *testing.T) {
	dir := t.TempDir()
	s, err := New(dir)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	body := map[string]interface{}{"result": map[string]interface{}{"success": true}}
	if err := s.Enqueue("42", body); err != nil {
		t.Fatalf("Enqueue: %v", err)
	}

	items, err := s.List()
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(items) != 1 || items[0].TaskID != "42" {
		t.Fatalf("unexpected items: %+v", items)
	}

	if err := s.Remove("42"); err != nil {
		t.Fatalf("Remove: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "42.json")); !os.IsNotExist(err) {
		t.Fatalf("expected file removed")
	 }
}
