//go:build !windows

package worldstore

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

func unsafeFileInfo(info os.FileInfo) bool {
	return info.Mode()&os.ModeSymlink != 0
}

func openRegularNoFollow(path string) (*os.File, error) {
	descriptor, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_CLOEXEC|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, err
	}
	file := os.NewFile(uintptr(descriptor), path)
	if file == nil {
		_ = syscall.Close(descriptor)
		return nil, fmt.Errorf("open returned an invalid descriptor")
	}
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		_ = file.Close()
		if err == nil {
			err = fmt.Errorf("path is not a regular file")
		}
		return nil, err
	}
	return file, nil
}

func replaceFileAtomic(source, destination string) error {
	if err := os.Rename(source, destination); err != nil {
		return err
	}
	return syncDirectory(filepath.Dir(destination))
}

func renameDirectoryAtomic(source, destination string) error {
	if err := os.Rename(source, destination); err != nil {
		return err
	}
	return syncDirectory(filepath.Dir(destination))
}

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}

func availableBytes(path string) (uint64, error) {
	var stats syscall.Statfs_t
	if err := syscall.Statfs(path, &stats); err != nil {
		return 0, err
	}
	return uint64(stats.Bavail) * uint64(stats.Bsize), nil
}

func sameFilesystem(left, right string) (bool, error) {
	leftInfo, err := os.Stat(left)
	if err != nil {
		return false, err
	}
	rightInfo, err := os.Stat(right)
	if err != nil {
		return false, err
	}
	leftStat, leftOK := leftInfo.Sys().(*syscall.Stat_t)
	rightStat, rightOK := rightInfo.Sys().(*syscall.Stat_t)
	if !leftOK || !rightOK {
		return false, fmt.Errorf("filesystem identity is unavailable")
	}
	return leftStat.Dev == rightStat.Dev, nil
}
