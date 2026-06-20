package client

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
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
