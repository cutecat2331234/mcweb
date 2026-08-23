//go:build windows

package worldstore

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

const (
	fileAttributeReparsePoint = 0x400
	moveFileReplaceExisting   = 0x1
	moveFileWriteThrough      = 0x8
)

var kernel32 = syscall.NewLazyDLL("kernel32.dll")
var moveFileExW = kernel32.NewProc("MoveFileExW")
var getDiskFreeSpaceExW = kernel32.NewProc("GetDiskFreeSpaceExW")

func unsafeFileInfo(info os.FileInfo) bool {
	if info.Mode()&os.ModeSymlink != 0 {
		return true
	}
	data, ok := info.Sys().(*syscall.Win32FileAttributeData)
	return ok && data.FileAttributes&fileAttributeReparsePoint != 0
}

func openRegularNoFollow(path string) (*os.File, error) {
	before, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if unsafeFileInfo(before) || !before.Mode().IsRegular() {
		return nil, fmt.Errorf("path is not a safe regular file")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	after, err := file.Stat()
	if err != nil || !after.Mode().IsRegular() || !os.SameFile(before, after) {
		_ = file.Close()
		if err == nil {
			err = fmt.Errorf("path identity changed while opening")
		}
		return nil, err
	}
	return file, nil
}

func replaceFileAtomic(source, destination string) error {
	return movePathWriteThrough(source, destination, true)
}

func renameDirectoryAtomic(source, destination string) error {
	return movePathWriteThrough(source, destination, false)
}

func movePathWriteThrough(source, destination string, replace bool) error {
	sourcePointer, err := syscall.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	destinationPointer, err := syscall.UTF16PtrFromString(destination)
	if err != nil {
		return err
	}
	flags := uintptr(moveFileWriteThrough)
	if replace {
		flags |= moveFileReplaceExisting
	}
	result, _, callErr := moveFileExW.Call(
		uintptr(unsafe.Pointer(sourcePointer)),
		uintptr(unsafe.Pointer(destinationPointer)),
		flags,
	)
	if result == 0 {
		if callErr != syscall.Errno(0) {
			return callErr
		}
		return fmt.Errorf("MoveFileExW failed")
	}
	return nil
}

func syncDirectory(string) error { return nil }

func availableBytes(path string) (uint64, error) {
	pointer, err := syscall.UTF16PtrFromString(filepath.Clean(path))
	if err != nil {
		return 0, err
	}
	var available, total, free uint64
	result, _, callErr := getDiskFreeSpaceExW.Call(
		uintptr(unsafe.Pointer(pointer)),
		uintptr(unsafe.Pointer(&available)),
		uintptr(unsafe.Pointer(&total)),
		uintptr(unsafe.Pointer(&free)),
	)
	if result == 0 {
		if callErr != syscall.Errno(0) {
			return 0, callErr
		}
		return 0, fmt.Errorf("GetDiskFreeSpaceExW failed")
	}
	return available, nil
}

func sameFilesystem(left, right string) (bool, error) {
	leftAbsolute, err := filepath.Abs(left)
	if err != nil {
		return false, err
	}
	rightAbsolute, err := filepath.Abs(right)
	if err != nil {
		return false, err
	}
	leftVolume := filepath.VolumeName(leftAbsolute)
	rightVolume := filepath.VolumeName(rightAbsolute)
	if leftVolume == "" || rightVolume == "" {
		return false, fmt.Errorf("filesystem identity is unavailable")
	}
	return strings.EqualFold(leftVolume, rightVolume), nil
}
