//go:build linux

package metrics

import (
	"bufio"
	"os"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

var (
	cpuMu       sync.Mutex
	lastCPUTime uint64
	lastIdle    uint64
	lastSample  time.Time
)

func cpuPercent() float64 {
	idle, total := readProcStat()
	if total == 0 {
		return 0
	}

	cpuMu.Lock()
	defer cpuMu.Unlock()

	if lastSample.IsZero() {
		lastIdle = idle
		lastCPUTime = total
		lastSample = time.Now()
		time.Sleep(200 * time.Millisecond)
		idle, total = readProcStat()
	}

	idleDelta := idle - lastIdle
	totalDelta := total - lastCPUTime
	lastIdle = idle
	lastCPUTime = total
	lastSample = time.Now()

	if totalDelta == 0 {
		return 0
	}
	used := totalDelta - idleDelta
	return float64(used) / float64(totalDelta) * 100
}

func readProcStat() (idle, total uint64) {
	f, err := os.Open("/proc/stat")
	if err != nil {
		return 0, 0
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	if !scanner.Scan() {
		return 0, 0
	}
	fields := strings.Fields(scanner.Text())
	if len(fields) < 5 || fields[0] != "cpu" {
		return 0, 0
	}

	for i := 1; i < len(fields); i++ {
		v, err := strconv.ParseUint(fields[i], 10, 64)
		if err != nil {
			continue
		}
		total += v
		if i == 4 {
			idle = v
		}
	}
	return idle, total
}

func memoryStats() (used, total uint64) {
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0, 0
	}
	defer f.Close()

	var memTotal, memAvailable uint64
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "MemTotal:"):
			memTotal = parseKB(line)
		case strings.HasPrefix(line, "MemAvailable:"):
			memAvailable = parseKB(line)
		}
	}
	if memTotal == 0 {
		return 0, 0
	}
	if memAvailable > memTotal {
		memAvailable = 0
	}
	return memTotal - memAvailable, memTotal
}

func parseKB(line string) uint64 {
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return 0
	}
	v, _ := strconv.ParseUint(fields[1], 10, 64)
	return v * 1024
}

func diskStats(path string) (used, total uint64) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return 0, 0
	}
	total = uint64(stat.Blocks) * uint64(stat.Bsize)
	free := uint64(stat.Bavail) * uint64(stat.Bsize)
	if total <= free {
		return 0, total
	}
	return total - free, total
}

func rootPath() string {
	return "/"
}
