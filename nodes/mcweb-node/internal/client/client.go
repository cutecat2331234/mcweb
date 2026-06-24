package client

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/mcweb/mcweb-node/internal/auth"
)

type HTTPError struct {
	StatusCode int
	Body       string
}

func (e *HTTPError) Error() string {
	return fmt.Sprintf("HTTP %d: %s", e.StatusCode, e.Body)
}

func IsPermanentHTTPError(err error) bool {
	var httpErr *HTTPError
	if !errors.As(err, &httpErr) {
		return false
	}
	if httpErr.StatusCode == http.StatusRequestTimeout || httpErr.StatusCode == http.StatusTooManyRequests {
		return false
	}
	return httpErr.StatusCode >= 400 && httpErr.StatusCode < 500
}

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
			time.Sleep(retryDelay(attempt))
			if body != nil {
				reader = bytes.NewReader([]byte(payload))
			}
			continue
		}

		data, _ := io.ReadAll(resp.Body)
		resp.Body.Close()

		if resp.StatusCode >= 500 {
			lastErr = fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(data))
			time.Sleep(retryDelay(attempt))
			if body != nil {
				reader = bytes.NewReader([]byte(payload))
			}
			continue
		}
		if resp.StatusCode >= 400 {
			return nil, &HTTPError{StatusCode: resp.StatusCode, Body: string(data)}
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

// retryDelay waits at least one second between attempts so each retry is signed with a
// distinct second-granular timestamp. A sub-second retry would reuse the previous
// timestamp+signature, which the server's HMAC replay guard rejects as a replay —
// silently dropping the (e.g. task-completion) request.
func retryDelay(attempt int) time.Duration {
	return time.Duration(1000*(attempt+1)) * time.Millisecond
}

func (c *Client) NodePath(suffix string) string {
	return fmt.Sprintf("/minecraft/nodes/%s/%s", c.nodeID, suffix)
}

// PollTaskWake checks whether urgent tasks are available without holding a long-lived connection.
func (c *Client) PollTaskWake(ctx context.Context, since string) (bool, string, error) {
	path := c.NodePath("events")
	if since != "" {
		path += "?since=" + url.QueryEscape(since)
	}

	ts := auth.Timestamp()
	sig := auth.Sign(c.secret, "", ts)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+path, nil)
	if err != nil {
		return false, "", err
	}
	req.Header.Set("X-Node-Timestamp", fmt.Sprintf("%d", ts))
	req.Header.Set("X-Node-Signature", sig)
	req.Header.Set("Accept", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false, "", err
	}
	defer resp.Body.Close()

	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusNoContent {
		return false, "", nil
	}
	if resp.StatusCode >= 400 {
		return false, "", fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(data))
	}

	var out map[string]interface{}
	if len(data) > 0 {
		if err := json.Unmarshal(data, &out); err != nil {
			return false, "", err
		}
	}
	wakeAt, _ := out["wake_at"].(string)
	return out["event"] == "tasks_available", wakeAt, nil
}
