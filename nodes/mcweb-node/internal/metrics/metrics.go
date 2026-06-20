package metrics

import (
	"math"
	"runtime"
	"time"
)

// Snapshot holds host resource utilization metrics.
type Snapshot struct {
	CPUPercent    float64
	MemoryPercent float64
	MemoryUsedMB  uint64
	MemoryTotalMB uint64
	DiskPercent   float64
	DiskUsedGB    float64
	DiskTotalGB   float64
	CollectedAt   string
	NumCPU        int
	OS            string
}

// Collect gathers current host CPU, memory, and disk utilization.
func Collect() Snapshot {
	snap := Snapshot{
		CollectedAt: time.Now().UTC().Format(time.RFC3339),
		NumCPU:      runtime.NumCPU(),
		OS:          runtime.GOOS,
	}

	snap.CPUPercent = cpuPercent()

	memUsed, memTotal := memoryStats()
	if memTotal > 0 {
		snap.MemoryUsedMB = memUsed / 1024 / 1024
		snap.MemoryTotalMB = memTotal / 1024 / 1024
		snap.MemoryPercent = float64(memUsed) / float64(memTotal) * 100
	}

	diskUsed, diskTotal := diskStats(rootPath())
	if diskTotal > 0 {
		snap.DiskUsedGB = float64(diskUsed) / 1024 / 1024 / 1024
		snap.DiskTotalGB = float64(diskTotal) / 1024 / 1024 / 1024
		snap.DiskPercent = float64(diskUsed) / float64(diskTotal) * 100
	}

	return snap
}

// CollectHost returns metrics as a JSON-friendly map for API payloads.
func CollectHost() map[string]interface{} {
	return Collect().ToMap()
}

// ToMap serializes the snapshot for Rails / heartbeat payloads.
func (s Snapshot) ToMap() map[string]interface{} {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	return map[string]interface{}{
		"cpu_percent":     round(s.CPUPercent),
		"memory_percent":  round(s.MemoryPercent),
		"memory_used_mb":  s.MemoryUsedMB,
		"memory_total_mb": s.MemoryTotalMB,
		"disk_percent":    round(s.DiskPercent),
		"disk_used_gb":    round(s.DiskUsedGB),
		"disk_total_gb":   round(s.DiskTotalGB),
		"collected_at":    s.CollectedAt,
		"num_cpu":         s.NumCPU,
		"os":              s.OS,
		"go_version":      runtime.Version(),
		"go_mem_alloc_mb": m.Alloc / 1024 / 1024,
	}
}

func round(v float64) float64 {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return 0
	}
	return math.Round(v*10) / 10
}
