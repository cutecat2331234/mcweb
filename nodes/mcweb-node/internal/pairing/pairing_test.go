package pairing

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPairExchangesOneTimeTokenForCredentials(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/minecraft/nodes/pair" {
			t.Fatalf("unexpected path: %s", request.URL.Path)
		}
		var payload map[string]string
		if err := json.NewDecoder(request.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		if payload["pairing_token"] != "one-time-token" || payload["hostname"] != "node-host" {
			t.Fatalf("unexpected payload: %+v", payload)
		}
		_ = json.NewEncoder(response).Encode(Credentials{NodeID: "node-1", NodeSecret: "secret-1"})
	}))
	defer server.Close()

	credentials, err := Pair(context.Background(), server.URL, "one-time-token", "node-host", false)
	if err != nil {
		t.Fatalf("Pair: %v", err)
	}
	if credentials.NodeID != "node-1" || credentials.NodeSecret != "secret-1" {
		t.Fatalf("unexpected credentials: %+v", credentials)
	}
}

func TestPairRejectsPlainHTTPForRemoteHosts(t *testing.T) {
	if _, err := validateRailsURL("http://example.com", false); err == nil {
		t.Fatal("expected insecure remote HTTP URL to be rejected")
	}
}
