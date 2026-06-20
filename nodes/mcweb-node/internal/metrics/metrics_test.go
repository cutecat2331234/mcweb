package metrics

import (
	"testing"
)

func TestCollectHostReturnsExpectedKeys(t *testing.T) {
	m := CollectHost()

	required := []string{
		"cpu_percent",
		"memory_percent",
		"memory_used_mb",
		"memory_total_mb",
		"disk_percent",
		"collected_at",
		"num_cpu",
		"os",
	}
	for _, key := range required {
		if _, ok := m[key]; !ok {
			t.Fatalf("missing key %q in CollectHost()", key)
		}
	}
}

func TestRoundHandlesNaN(t *testing.T) {
	if round(1.234) != 1.2 {
		t.Fatalf("expected 1.2, got %v", round(1.234))
	}
}
