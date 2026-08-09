package pairing

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Credentials struct {
	NodeID     string `json:"node_id"`
	NodeSecret string `json:"node_secret"`
}

func Pair(ctx context.Context, railsURL, token, hostname string, allowInsecureHTTP bool) (Credentials, error) {
	baseURL, err := validateRailsURL(railsURL, allowInsecureHTTP)
	if err != nil {
		return Credentials{}, err
	}
	if strings.TrimSpace(token) == "" {
		return Credentials{}, fmt.Errorf("pairing token is required")
	}
	body, err := json.Marshal(map[string]string{
		"pairing_token": strings.TrimSpace(token),
		"hostname":      hostname,
	})
	if err != nil {
		return Credentials{}, err
	}

	request, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		strings.TrimRight(baseURL.String(), "/")+"/minecraft/nodes/pair",
		bytes.NewReader(body),
	)
	if err != nil {
		return Credentials{}, err
	}
	request.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 30 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		return Credentials{}, err
	}
	defer response.Body.Close()
	responseBody, _ := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return Credentials{}, fmt.Errorf("pairing failed with HTTP %d: %s", response.StatusCode, strings.TrimSpace(string(responseBody)))
	}

	var credentials Credentials
	if err := json.Unmarshal(responseBody, &credentials); err != nil {
		return Credentials{}, err
	}
	if credentials.NodeID == "" || credentials.NodeSecret == "" {
		return Credentials{}, fmt.Errorf("pairing response omitted node credentials")
	}
	return credentials, nil
}

func validateRailsURL(raw string, allowInsecureHTTP bool) (*url.URL, error) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed.Hostname() == "" {
		return nil, fmt.Errorf("valid rails URL is required")
	}
	if parsed.Scheme == "https" {
		return parsed, nil
	}
	if parsed.Scheme == "http" && (allowInsecureHTTP || isLoopback(parsed.Hostname())) {
		return parsed, nil
	}
	return nil, fmt.Errorf("rails URL must use HTTPS; use --allow-insecure-http only on a trusted network")
}

func isLoopback(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(strings.Trim(host, "[]"))
	return ip != nil && ip.IsLoopback()
}
