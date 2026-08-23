package worldstore

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func ensureSafeCreationAncestors(path string) error {
	current := filepath.Clean(path)
	for {
		info, err := os.Lstat(current)
		if err == nil {
			if unsafeFileInfo(info) || !info.IsDir() {
				return fail("configured_path_ancestor_unsafe", nil)
			}
			return ensureSafeConfiguredPath(current)
		}
		if !os.IsNotExist(err) {
			return fail("configured_path_ancestor_unreadable", err)
		}
		parent := filepath.Dir(current)
		if parent == current {
			return fail("configured_path_ancestor_missing", nil)
		}
		current = parent
	}
}

func ensureSafeConfiguredPath(path string) error {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return fail("configured_path_invalid", err)
	}
	clean := filepath.Clean(absolute)
	volume := filepath.VolumeName(clean)
	remainder := strings.TrimPrefix(clean, volume)
	remainder = strings.TrimLeft(remainder, `/\`)
	current := volume + string(filepath.Separator)
	if volume == "" {
		current = string(filepath.Separator)
	}

	if info, statErr := os.Lstat(current); statErr != nil {
		return fail("configured_path_unreadable", statErr)
	} else if unsafeFileInfo(info) {
		return fail("configured_path_link_forbidden", nil)
	}
	for _, component := range strings.FieldsFunc(remainder, func(r rune) bool { return r == '/' || r == '\\' }) {
		current = filepath.Join(current, component)
		info, statErr := os.Lstat(current)
		if statErr != nil {
			return fail("configured_path_unreadable", statErr)
		}
		if unsafeFileInfo(info) {
			return fail("configured_path_link_forbidden", fmt.Errorf("unsafe component"))
		}
	}
	info, err := os.Stat(clean)
	if err != nil || !info.IsDir() {
		return fail("configured_path_not_directory", err)
	}
	return nil
}

func ensureSafeRelativeComponents(root, relative string) error {
	current := filepath.Clean(root)
	parts := strings.Split(filepath.FromSlash(relative), string(filepath.Separator))
	for position, component := range parts {
		current = filepath.Join(current, component)
		info, err := os.Lstat(current)
		if os.IsNotExist(err) {
			return nil
		}
		if err != nil {
			return fail("world_path_component_unreadable", err)
		}
		if unsafeFileInfo(info) {
			return fail("world_path_component_link_forbidden", nil)
		}
		if position < len(parts)-1 && !info.IsDir() {
			return fail("world_path_component_not_directory", nil)
		}
	}
	return nil
}

func renameDirectory(source, destination string) error {
	return renameDirectoryAtomic(source, destination)
}

func safeAuxiliaryPath(livePath, candidate, marker, planID string) error {
	parent := filepath.Dir(livePath)
	expectedName := ".mcweb-world-restore-" + planID + "-" + marker
	if filepath.Clean(candidate) != filepath.Join(parent, expectedName) {
		return fail("restore_ledger_path_invalid", nil)
	}
	return nil
}

func removeAuxiliaryTree(livePath, candidate, marker, planID string) error {
	if err := safeAuxiliaryPath(livePath, candidate, marker, planID); err != nil {
		return err
	}
	info, err := os.Lstat(candidate)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if unsafeFileInfo(info) || !info.IsDir() {
		return fail("restore_auxiliary_path_unsafe", nil)
	}
	return os.RemoveAll(candidate)
}

func pathExists(path string) (bool, error) {
	_, err := os.Lstat(path)
	if os.IsNotExist(err) {
		return false, nil
	}
	return err == nil, err
}
