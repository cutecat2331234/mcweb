package proxy

import (
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"sync"
	"time"
)

type Stats struct {
	mu          sync.RWMutex
	lastRequest map[string]time.Time
	lastSuccess map[string]time.Time
	lastError   map[string]string
}

func NewStats() *Stats {
	return &Stats{
		lastRequest: make(map[string]time.Time),
		lastSuccess: make(map[string]time.Time),
		lastError:   make(map[string]string),
	}
}

func (s *Stats) Record(serverID string, success bool, errMsg string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	s.lastRequest[serverID] = now
	if success {
		s.lastSuccess[serverID] = now
		delete(s.lastError, serverID)
	} else {
		s.lastError[serverID] = errMsg
	}
}

func (s *Stats) Snapshot() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make(map[string]interface{})
	for id, t := range s.lastRequest {
		entry := map[string]interface{}{
			"last_request_at": t.UTC().Format(time.RFC3339),
		}
		if ts, ok := s.lastSuccess[id]; ok {
			entry["last_success_at"] = ts.UTC().Format(time.RFC3339)
		}
		if msg, ok := s.lastError[id]; ok {
			entry["last_error"] = msg
		}
		out[id] = entry
	}
	return out
}

func extractServerID(path string) string {
	parts := strings.Split(strings.Trim(path, "/"), "/")
	// minecraft/connector/:server_id/...
	if len(parts) >= 3 && parts[0] == "minecraft" && parts[1] == "connector" {
		return parts[2]
	}
	return ""
}

func New(railsURL string, stats *Stats) (*http.Server, error) {
	target, err := url.Parse(railsURL)
	if err != nil {
		return nil, err
	}
	proxy := httputil.NewSingleHostReverseProxy(target)
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Host = target.Host
	}
	proxy.ModifyResponse = func(resp *http.Response) error {
		serverID := extractServerID(resp.Request.URL.Path)
		if serverID != "" {
			stats.Record(serverID, resp.StatusCode < 400, "")
		}
		return nil
	}
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		serverID := extractServerID(r.URL.Path)
		if serverID != "" {
			stats.Record(serverID, false, err.Error())
		}
		log.Printf("proxy error server=%s path=%s: %v", serverID, r.URL.Path, err)
		http.Error(w, "bad gateway", http.StatusBadGateway)
	}

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/minecraft/connector/") {
			http.NotFound(w, r)
			return
		}
		serverID := extractServerID(r.URL.Path)
		if serverID != "" {
			stats.Record(serverID, true, "")
		}
		proxy.ServeHTTP(w, r)
	})

	return &http.Server{Handler: handler}, nil
}

func ListenAndServe(listen string, railsURL string, stats *Stats) error {
	srv, err := New(railsURL, stats)
	if err != nil {
		return err
	}
	srv.Addr = listen
	log.Printf("connector proxy listening on %s -> %s", listen, railsURL)
	return srv.ListenAndServe()
}

// Unused import guard for io in case of future body logging
var _ = io.Discard
