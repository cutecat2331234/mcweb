//go:build !linux && !windows

package metrics

func cpuPercent() float64 {
	return 0
}

func memoryStats() (used, total uint64) {
	return 0, 0
}

func diskStats(path string) (used, total uint64) {
	return 0, 0
}

func rootPath() string {
	return "/"
}
