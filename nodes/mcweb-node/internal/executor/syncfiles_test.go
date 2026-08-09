package executor

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSyncFilesVerifiesDigestAndAtomicallyUpdatesRelativeTarget(t *testing.T) {
	content := []byte("plugin-data-v2")
	digest := sha256.Sum256(content)
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		_, _ = response.Write(content)
	}))
	defer server.Close()

	root := t.TempDir()
	result := New().syncFiles(context.Background(), map[string]interface{}{
		"url":               server.URL + "/minecraft/sync/test-token",
		"working_directory": root,
		"relative_path":     "plugins/example.jar",
		"sha256":            hex.EncodeToString(digest[:]),
		"revision":          "rev-2",
	})
	if result["success"] != true {
		t.Fatalf("sync failed: %+v", result)
	}
	data, err := os.ReadFile(filepath.Join(root, "plugins", "example.jar"))
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(data) != string(content) || result["applied_revision"] != "rev-2" {
		t.Fatalf("unexpected result=%+v data=%q", result, data)
	}
}

func TestSyncFilesDoesNotReplaceTargetOnDigestMismatch(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		_, _ = response.Write([]byte("corrupt"))
	}))
	defer server.Close()

	root := t.TempDir()
	destination := filepath.Join(root, "server.properties")
	if err := os.WriteFile(destination, []byte("known-good"), 0o600); err != nil {
		t.Fatal(err)
	}
	result := New().syncFiles(context.Background(), map[string]interface{}{
		"url":               server.URL + "/minecraft/sync/test-token",
		"working_directory": root,
		"relative_path":     "server.properties",
		"sha256":            strings.Repeat("0", 64),
		"revision":          "rev-bad",
	})
	if result["success"] != false {
		t.Fatalf("expected failure: %+v", result)
	}
	data, err := os.ReadFile(destination)
	if err != nil || string(data) != "known-good" {
		t.Fatalf("destination changed: data=%q err=%v", data, err)
	}
}
