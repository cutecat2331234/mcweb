package executor

import "testing"

func TestValidateSyncURL(t *testing.T) {
	if err := validateSyncURL("https://example.com/minecraft/sync/token"); err != nil {
		t.Fatalf("expected public https url to pass: %v", err)
	}
	if err := validateSyncURL("http://127.0.0.1:3000/minecraft/sync/token"); err != nil {
		t.Fatalf("expected loopback http url to pass: %v", err)
	}
	if err := validateSyncURL("http://169.254.169.254/minecraft/sync/token"); err == nil {
		t.Fatal("expected metadata host to be blocked")
	}
	if err := validateSyncURL("https://example.com/other/path"); err == nil {
		t.Fatal("expected non-sync path to be blocked")
	}
}
