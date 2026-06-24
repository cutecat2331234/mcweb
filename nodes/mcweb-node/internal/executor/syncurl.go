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

	// Resolve the host and reject if ANY resolved address is non-public. Previously only
	// literal private IPs were rejected, so a public hostname with an A/AAAA record
	// pointing at an internal/metadata/private address bypassed the SSRF guard. Resolving
	// here also covers the literal-IP case (LookupIP returns the literal unchanged).
	// Note: this does not close DNS-rebinding (curl re-resolves); pinning the resolved IP
	// would require replacing the curl shell-out.
	ips, err := net.LookupIP(host)
	if err != nil {
		return fmt.Errorf("sync url host resolution failed: %w", err)
	}
	if len(ips) == 0 {
		return fmt.Errorf("sync url host did not resolve")
	}
	for _, ip := range ips {
		if !isPublicIP(ip) {
			return fmt.Errorf("sync url host resolves to a non-public address")
		}
	}
	return nil
}

func isPublicIP(ip net.IP) bool {
	if ip == nil {
		return false
	}
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() ||
		ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.IsMulticast() {
		return false
	}
	// Cloud metadata endpoint (link-local range already covers 169.254/16, but be explicit).
	if ip.Equal(net.ParseIP("169.254.169.254")) {
		return false
	}
	return true
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
