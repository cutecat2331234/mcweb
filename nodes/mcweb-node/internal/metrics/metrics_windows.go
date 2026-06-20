//go:build windows

package metrics

import (
	"syscall"
	"unsafe"
)

var (
	kernel32         = syscall.NewLazyDLL("kernel32.dll")
	globalMemoryStatus = kernel32.NewProc("GlobalMemoryStatusEx")
	getDiskFreeSpaceEx = kernel32.NewProc("GetDiskFreeSpaceExW")
)

type memoryStatusEx struct {
	Length               uint32
	MemoryLoad           uint32
	TotalPhys            uint64
	AvailPhys            uint64
	TotalPageFile        uint64
	AvailPageFile        uint64
	TotalVirtual         uint64
	AvailVirtual         uint64
	AvailExtendedVirtual uint64
}

func cpuPercent() float64 {
	// Per-process CPU sampling is unreliable without PDH; return 0 on Windows dev hosts.
	return 0
}

func memoryStats() (used, total uint64) {
	var status memoryStatusEx
	status.Length = uint32(unsafe.Sizeof(status))
	r, _, _ := globalMemoryStatus.Call(uintptr(unsafe.Pointer(&status)))
	if r == 0 {
		return 0, 0
	}
	total = status.TotalPhys
	used = status.TotalPhys - status.AvailPhys
	return used, total
}

func diskStats(path string) (used, total uint64) {
	p, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return 0, 0
	}
	var freeBytes, totalBytes, totalFree uint64
	r, _, _ := getDiskFreeSpaceEx.Call(
		uintptr(unsafe.Pointer(p)),
		uintptr(unsafe.Pointer(&freeBytes)),
		uintptr(unsafe.Pointer(&totalBytes)),
		uintptr(unsafe.Pointer(&totalFree)),
	)
	if r == 0 {
		return 0, 0
	}
	used = totalBytes - freeBytes
	return used, totalBytes
}

func rootPath() string {
	return "C:\\"
}
