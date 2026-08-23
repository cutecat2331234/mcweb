package worldstore

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"unicode/utf8"
)

var managedIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{8,128}$`)
var sha256Pattern = regexp.MustCompile(`^[0-9a-f]{64}$`)

var reservedWindowsNames = map[string]struct{}{
	"CON": {}, "PRN": {}, "AUX": {}, "NUL": {}, "CLOCK$": {}, "CONIN$": {}, "CONOUT$": {},
}

func validateManagedID(value string) error {
	if !managedIDPattern.MatchString(value) {
		return fail("managed_id_invalid", nil)
	}
	return nil
}

func validateSHA256(value string) error {
	if !sha256Pattern.MatchString(value) {
		return fail("sha256_invalid", nil)
	}
	return nil
}

func ValidateRelativePath(value string, limits Limits) (string, error) {
	limits = NormalizeLimits(limits)
	if value == "" || value != strings.TrimSpace(value) || !utf8.ValidString(value) {
		return "", fail("archive_path_invalid", nil)
	}
	if len(value) > limits.MaxPathBytes || strings.HasPrefix(value, "/") || strings.HasPrefix(value, `\`) {
		return "", fail("archive_path_invalid", nil)
	}
	if strings.ContainsAny(value, `\:`) {
		return "", fail("archive_path_invalid", nil)
	}

	parts := strings.Split(value, "/")
	if len(parts) == 0 || len(parts) > limits.MaxDepth {
		return "", fail("archive_path_depth_exceeded", nil)
	}
	for _, part := range parts {
		if err := validatePathComponent(part); err != nil {
			return "", err
		}
	}
	return strings.Join(parts, "/"), nil
}

func validatePathComponent(part string) error {
	if part == "" || part == "." || part == ".." || len(part) > 255 {
		return fail("archive_path_component_invalid", nil)
	}
	if strings.HasSuffix(part, ".") || strings.HasSuffix(part, " ") {
		return fail("archive_path_component_invalid", nil)
	}
	if strings.ContainsAny(part, `<>"|?*`) {
		return fail("archive_path_component_invalid", nil)
	}
	for _, r := range part {
		if r < 0x20 || r == 0x7f {
			return fail("archive_path_control_character", nil)
		}
		// A conservative portable-name profile makes case folding and filesystem
		// equivalence deterministic across Linux and Windows without normalization
		// dependencies. Minecraft's managed world layout uses ASCII names.
		if r > 0x7e {
			return fail("archive_path_nonportable_unicode", nil)
		}
	}

	base := strings.ToUpper(strings.SplitN(part, ".", 2)[0])
	if _, reserved := reservedWindowsNames[base]; reserved {
		return fail("archive_path_reserved_name", nil)
	}
	if len(base) == 4 && (strings.HasPrefix(base, "COM") || strings.HasPrefix(base, "LPT")) &&
		base[3] >= '1' && base[3] <= '9' {
		return fail("archive_path_reserved_name", nil)
	}
	return nil
}

type collisionKind uint8

const (
	collisionFile collisionKind = iota + 1
	collisionDirectory
)

type collisionIndex struct {
	entries        map[string]collisionKind
	folded         map[string]string
	hasDescendants map[string]struct{}
}

func newCollisionIndex() *collisionIndex {
	return &collisionIndex{
		entries:        make(map[string]collisionKind),
		folded:         make(map[string]string),
		hasDescendants: make(map[string]struct{}),
	}
}

func (index *collisionIndex) Add(path string, directory bool) error {
	kind := collisionFile
	if directory {
		kind = collisionDirectory
	}
	if _, exists := index.entries[path]; exists {
		return fail("archive_duplicate_path", nil)
	}
	folded := strings.ToLower(path)
	if previous, exists := index.folded[folded]; exists && previous != path {
		return fail("archive_case_collision", fmt.Errorf("%s conflicts with %s", path, previous))
	}
	if kind == collisionFile {
		if _, exists := index.hasDescendants[path]; exists {
			return fail("archive_prefix_collision", nil)
		}
	}

	parts := strings.Split(path, "/")
	for i := 1; i < len(parts); i++ {
		prefix := strings.Join(parts[:i], "/")
		if index.entries[prefix] == collisionFile {
			return fail("archive_prefix_collision", nil)
		}
		index.hasDescendants[prefix] = struct{}{}
	}
	index.entries[path] = kind
	index.folded[folded] = path
	return nil
}

func resolveWorldPath(workingDirectory, relative string, limits Limits) (string, error) {
	if workingDirectory == "" {
		return "", fail("working_directory_required", nil)
	}
	cleanRelative, err := ValidateRelativePath(relative, limits)
	if err != nil {
		return "", err
	}
	root, err := filepath.Abs(workingDirectory)
	if err != nil {
		return "", fail("working_directory_invalid", err)
	}
	if err := ensureSafeConfiguredPath(root); err != nil {
		return "", err
	}
	if err := ensureSafeRelativeComponents(root, cleanRelative); err != nil {
		return "", err
	}
	world := root
	for _, part := range strings.Split(cleanRelative, "/") {
		world = filepath.Join(world, part)
	}
	rel, err := filepath.Rel(root, world)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fail("world_path_escapes_working_directory", err)
	}
	return world, nil
}

func pathsOverlap(left, right string) bool {
	left = filepath.Clean(left)
	right = filepath.Clean(right)
	return pathContains(left, right) || pathContains(right, left)
}

func pathContains(root, candidate string) bool {
	relative, err := filepath.Rel(root, candidate)
	return err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator))
}
