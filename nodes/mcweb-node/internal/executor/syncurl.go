package executor

import (
	"fmt"
	"net"
	"net/url"
	"strings"
)

func validateSyncURL(raw string) error {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return fmt.Errorf("invalid sync url: %w", err)
	}
	if parsed.Scheme != "https" && !(parsed.Scheme == "http" && isLoopbackHost(parsed.Hostname())) {
		return fmt.Errorf("sync url scheme not allowed")
	}
	if !strings.Contains(parsed.Path, "/minecraft/sync/") {
		return fmt.Errorf("sync url path not allowed")
	}

	host := strings.ToLower(parsed.Hostname())
	if host == "" {
		return fmt.Errorf("sync url host required")
	}
	if isLoopbackHost(host) {
		return nil
	}
	if blockedSyncHost(host) {
		return fmt.Errorf("sync url host blocked")
	}
	if ip := net.ParseIP(host); ip != nil {
		if ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() {
			return fmt.Errorf("sync url host not allowed")
		}
	}
	return nil
}

func isLoopbackHost(host string) bool {
	host = strings.Trim(host, "[]")
	if host == "localhost" || host == "127.0.0.1" || host == "::1" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func blockedSyncHost(host string) bool {
	switch host {
	case "metadata.google.internal", "169.254.169.254", "0.0.0.0":
		return true
	default:
		return strings.HasSuffix(host, ".local") || strings.HasSuffix(host, ".internal") || strings.HasSuffix(host, ".localhost")
	}
}
