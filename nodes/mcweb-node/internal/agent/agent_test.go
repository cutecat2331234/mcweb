package agent

import "testing"

func TestMergePayloadsKeepsSharedValuesAndAppliesTargetOverrides(t *testing.T) {
	merged := mergePayloads(
		map[string]interface{}{"url": "shared", "revision": "v1"},
		map[string]interface{}{"revision": "v2", "server_id": "server-1"},
	)
	if merged["url"] != "shared" || merged["revision"] != "v2" || merged["server_id"] != "server-1" {
		t.Fatalf("unexpected merged payload: %+v", merged)
	}
}
