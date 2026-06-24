package executor

import (
	"net"
	"testing"
)

func TestValidateSyncURL(t *testing.T) {
	// Literal IPs are resolved locally by net.LookupIP (no DNS), so these are deterministic.
	cases := []struct {
		name    string
		url     string
		wantErr bool
	}{
		{"public literal ip", "https://8.8.8.8/minecraft/sync/token", false},
		{"loopback https", "https://127.0.0.1/minecraft/sync/token", false},
		{"loopback http allowed", "http://127.0.0.1:3000/minecraft/sync/token", false},
		{"private 10/8", "https://10.0.0.5/minecraft/sync/token", true},
		{"private 172.16", "https://172.16.0.1/minecraft/sync/token", true},
		{"private 192.168", "https://192.168.1.10/minecraft/sync/token", true},
		{"link-local metadata", "https://169.254.169.254/minecraft/sync/token", true},
		{"unspecified", "https://0.0.0.0/minecraft/sync/token", true},
		{"non-loopback http scheme", "http://1.2.3.4/minecraft/sync/token", true},
		{"wrong path", "https://8.8.8.8/other/path", true},
		{"blocked internal suffix", "https://foo.internal/minecraft/sync/token", true},
		{"empty", "", true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateSyncURL(tc.url)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error for %q, got nil", tc.url)
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("expected no error for %q, got %v", tc.url, err)
			}
		})
	}
}

func TestIsPublicIP(t *testing.T) {
	nonPublic := []string{"127.0.0.1", "::1", "10.1.2.3", "172.16.0.1", "192.168.0.1", "169.254.169.254", "0.0.0.0", "::"}
	for _, s := range nonPublic {
		if isPublicIP(net.ParseIP(s)) {
			t.Errorf("expected %s to be non-public", s)
		}
	}
	public := []string{"8.8.8.8", "1.1.1.1", "2606:4700:4700::1111"}
	for _, s := range public {
		if !isPublicIP(net.ParseIP(s)) {
			t.Errorf("expected %s to be public", s)
		}
	}
}
