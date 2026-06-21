package client

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/mcweb/mcweb-node/internal/auth"
)

type Client struct {
	baseURL    string
	nodeID     string
	secret     string
	httpClient *http.Client
}

func New(baseURL, nodeID, secret string) *Client {
	base := baseURL
	if len(base) > 0 && base[len(base)-1] == '/' {
		base = base[:len(base)-1]
	}
	return &Client{
		baseURL: base,
		nodeID:  nodeID,
		secret:  secret,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (c *Client) Get(path string) (map[string]interface{}, error) {
	return c.do(http.MethodGet, path, nil)
}

func (c *Client) Post(path string, body interface{}) (map[string]interface{}, error) {
	return c.do(http.MethodPost, path, body)
}

func (c *Client) do(method, path string, body interface{}) (map[string]interface{}, error) {
	var payload string
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		payload = string(b)
		reader = bytes.NewReader(b)
	}

	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		ts := auth.Timestamp()
		sig := auth.Sign(c.secret, payload, ts)

		req, err := http.NewRequest(method, c.baseURL+path, reader)
		if err != nil {
			return nil, err
		}
		req.Header.Set("X-Node-Timestamp", fmt.Sprintf("%d", ts))
		req.Header.Set("X-Node-Signature", sig)
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			lastErr = err
			time.Sleep(time.Duration(500*(attempt+1)) * time.Millisecond)
			if body != nil {
				reader = bytes.NewReader([]byte(payload))
			}
			continue
		}

		data, _ := io.ReadAll(resp.Body)
		resp.Body.Close()

		if resp.StatusCode >= 500 {
			lastErr = fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(data))
			time.Sleep(time.Duration(500*(attempt+1)) * time.Millisecond)
			if body != nil {
				reader = bytes.NewReader([]byte(payload))
			}
			continue
		}
		if resp.StatusCode >= 400 {
			return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(data))
		}

		var out map[string]interface{}
		if len(data) > 0 {
			if err := json.Unmarshal(data, &out); err != nil {
				return nil, err
			}
		}
		return out, nil
	}
	return nil, lastErr
}

func (c *Client) NodePath(suffix string) string {
	return fmt.Sprintf("/minecraft/nodes/%s/%s", c.nodeID, suffix)
}

// StreamEvents opens the Rails SSE push channel until ctx is cancelled or an event arrives.
func (c *Client) StreamEvents(ctx context.Context, since string, onEvent func(event string)) error {
	path := c.NodePath("events")
	if since != "" {
		path += "?since=" + since
	}

	ts := auth.Timestamp()
	sig := auth.Sign(c.secret, "", ts)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("X-Node-Timestamp", fmt.Sprintf("%d", ts))
	req.Header.Set("X-Node-Signature", sig)
	req.Header.Set("Accept", "text/event-stream")

	client := &http.Client{Timeout: 70 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		data, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(data))
	}

	scanner := bufio.NewScanner(resp.Body)
	var eventName string
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "event:") {
			eventName = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
		}
		if line == "" && eventName != "" {
			onEvent(eventName)
			return nil
		}
	}
	return scanner.Err()
}
