package worldstore

import (
	"archive/tar"
	"bufio"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type sourceEntry struct {
	path      string
	fullPath  string
	directory bool
	size      int64
	info      os.FileInfo
}

func writeManagedArchive(
	ctx context.Context,
	archivePath string,
	sourcePath string,
	limits Limits,
) ([]ManifestEntry, int64, int64, string, error) {
	limits = NormalizeLimits(limits)
	entries, total, directories, state, err := inspectSourceTree(ctx, sourcePath, limits)
	if err != nil {
		return nil, 0, 0, "", err
	}

	file, err := os.OpenFile(archivePath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, 0, 0, "", fail("backup_archive_create_failed", err)
	}
	keep := false
	defer func() {
		_ = file.Close()
		if !keep {
			_ = os.Remove(archivePath)
		}
	}()

	gzipWriter := gzip.NewWriter(file)
	gzipWriter.Name = ""
	gzipWriter.Comment = ""
	gzipWriter.ModTime = time.Unix(0, 0).UTC()
	gzipWriter.OS = 255
	tarWriter := tar.NewWriter(gzipWriter)
	manifestEntries := make([]ManifestEntry, 0, len(entries))
	for _, entry := range entries {
		if err := ctx.Err(); err != nil {
			return nil, 0, 0, "", fail("backup_cancelled", err)
		}
		header := &tar.Header{
			Name:       entry.path,
			Mode:       0o600,
			Size:       entry.size,
			Typeflag:   tar.TypeReg,
			ModTime:    time.Unix(0, 0).UTC(),
			AccessTime: time.Time{},
			ChangeTime: time.Time{},
			Format:     tar.FormatPAX,
		}
		if entry.directory {
			header.Name += "/"
			header.Mode = 0o700
			header.Size = 0
			header.Typeflag = tar.TypeDir
		}
		if err := tarWriter.WriteHeader(header); err != nil {
			return nil, 0, 0, "", fail("backup_archive_header_failed", err)
		}
		manifestEntry := ManifestEntry{Path: entry.path, Type: "directory", Size: 0}
		if !entry.directory {
			digest, err := writeSourceFile(tarWriter, entry)
			if err != nil {
				return nil, 0, 0, "", err
			}
			manifestEntry.Type = "file"
			manifestEntry.Size = entry.size
			manifestEntry.SHA256 = digest
		}
		manifestEntries = append(manifestEntries, manifestEntry)
	}
	if err := tarWriter.Close(); err != nil {
		return nil, 0, 0, "", fail("backup_archive_finalize_failed", err)
	}
	if err := gzipWriter.Close(); err != nil {
		return nil, 0, 0, "", fail("backup_archive_finalize_failed", err)
	}
	if err := file.Sync(); err != nil {
		return nil, 0, 0, "", fail("backup_archive_sync_failed", err)
	}
	if err := file.Close(); err != nil {
		return nil, 0, 0, "", fail("backup_archive_close_failed", err)
	}
	keep = true
	return manifestEntries, total, directories, state, nil
}

func inspectSourceTree(ctx context.Context, sourcePath string, limits Limits) ([]sourceEntry, int64, int64, string, error) {
	info, err := os.Lstat(sourcePath)
	if os.IsNotExist(err) {
		return nil, 0, 0, "absent", nil
	}
	if err != nil {
		return nil, 0, 0, "", fail("world_source_unreadable", err)
	}
	if unsafeFileInfo(info) || !info.IsDir() {
		return nil, 0, 0, "", fail("world_source_unsafe", nil)
	}

	index := newCollisionIndex()
	entries := make([]sourceEntry, 0)
	var total, directories int64
	err = filepath.WalkDir(sourcePath, func(path string, directoryEntry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		relative, err := filepath.Rel(sourcePath, path)
		if err != nil {
			return err
		}
		if relative == "." {
			return nil
		}
		portable := filepath.ToSlash(relative)
		clean, err := ValidateRelativePath(portable, limits)
		if err != nil || clean != portable {
			return fail("world_source_path_invalid", err)
		}
		fileInfo, err := directoryEntry.Info()
		if err != nil {
			return err
		}
		if unsafeFileInfo(fileInfo) {
			return fail("world_source_link_forbidden", nil)
		}
		directory := fileInfo.IsDir()
		if !directory && !fileInfo.Mode().IsRegular() {
			return fail("world_source_special_file_forbidden", nil)
		}
		if err := index.Add(clean, directory); err != nil {
			return err
		}
		if int64(len(entries))+1 > limits.MaxEntries {
			return fail("world_source_entry_quota_exceeded", nil)
		}
		if directory {
			directories++
			if directories > limits.MaxDirectories {
				return fail("world_source_directory_quota_exceeded", nil)
			}
		} else {
			if fileInfo.Size() < 0 || fileInfo.Size() > limits.MaxFileBytes {
				return fail("world_source_file_quota_exceeded", nil)
			}
			total += fileInfo.Size()
			if total > limits.MaxUncompressedBytes {
				return fail("world_source_size_quota_exceeded", nil)
			}
		}
		entries = append(entries, sourceEntry{
			path: clean, fullPath: path, directory: directory, size: fileInfo.Size(), info: fileInfo,
		})
		return nil
	})
	if err != nil {
		return nil, 0, 0, "", fail(errorCode(err, "world_source_scan_failed"), err)
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].path < entries[j].path })
	return entries, total, directories, "present", nil
}

func writeSourceFile(destination io.Writer, entry sourceEntry) (string, error) {
	file, err := openRegularNoFollow(entry.fullPath)
	if err != nil {
		return "", fail("world_source_file_open_failed", err)
	}
	defer file.Close()
	currentInfo, err := file.Stat()
	if err != nil || !os.SameFile(entry.info, currentInfo) || currentInfo.Size() != entry.size {
		return "", fail("world_source_changed", err)
	}
	hasher := sha256.New()
	written, err := io.CopyN(io.MultiWriter(destination, hasher), file, entry.size)
	if err != nil || written != entry.size {
		return "", fail("world_source_truncated", err)
	}
	var extra [1]byte
	if count, readErr := file.Read(extra[:]); count != 0 || (readErr != nil && readErr != io.EOF) {
		return "", fail("world_source_changed", readErr)
	}
	return hex.EncodeToString(hasher.Sum(nil)), nil
}

func validateArchiveFile(path string, manifest *Manifest, limits Limits) error {
	digest, size, err := digestFile(path, NormalizeLimits(limits).MaxArchiveBytes)
	if err != nil {
		return fail("archive_digest_failed", err)
	}
	if size != manifest.ArchiveBytes || digest != manifest.ArchiveSHA256 {
		return fail("archive_digest_mismatch", nil)
	}
	if manifest.UncompressedBytes > 0 && manifest.ArchiveBytes > 0 &&
		float64(manifest.UncompressedBytes)/float64(manifest.ArchiveBytes) > NormalizeLimits(limits).MaxExpansionRatio {
		return fail("archive_expansion_ratio_exceeded", nil)
	}
	return nil
}

func scanOrExtractArchive(manifest *Manifest, archivePath, destination string, limits Limits) error {
	limits = NormalizeLimits(limits)
	if err := validateArchiveFile(archivePath, manifest, limits); err != nil {
		return err
	}
	file, err := openRegularNoFollow(archivePath)
	if err != nil {
		return fail("archive_open_failed", err)
	}
	defer file.Close()
	buffered := bufio.NewReader(file)
	gzipReader, err := gzip.NewReader(buffered)
	if err != nil {
		return fail("archive_gzip_invalid", err)
	}
	gzipReader.Multistream(false)
	defer gzipReader.Close()
	decompressionLimit := archiveDecompressionLimit(manifest, limits)
	limitedStream := &io.LimitedReader{R: gzipReader, N: decompressionLimit + 1}
	tarReader := tar.NewReader(limitedStream)
	index := newCollisionIndex()
	var total, directories int64

	for position, expected := range manifest.Entries {
		header, err := tarReader.Next()
		if err != nil {
			if limitedStream.N == 0 {
				return fail("archive_decompression_quota_exceeded", err)
			}
			return fail("archive_truncated", err)
		}
		path, directory, err := normalizeArchiveHeader(header, limits)
		if err != nil {
			return err
		}
		if path != expected.Path || directory != (expected.Type == "directory") || header.Size != expected.Size {
			return fail("archive_manifest_entry_mismatch", fmt.Errorf("entry %d", position))
		}
		if err := index.Add(path, directory); err != nil {
			return err
		}
		if int64(position)+1 > limits.MaxEntries {
			return fail("archive_entry_quota_exceeded", nil)
		}

		if directory {
			directories++
			if directories > limits.MaxDirectories {
				return fail("archive_directory_quota_exceeded", nil)
			}
			if destination != "" {
				if err := extractDirectory(destination, path); err != nil {
					return err
				}
			}
			continue
		}
		total += header.Size
		if header.Size > limits.MaxFileBytes || total > limits.MaxUncompressedBytes {
			return fail("archive_size_quota_exceeded", nil)
		}
		if err := consumeArchiveFile(tarReader, destination, path, expected); err != nil {
			if limitedStream.N == 0 {
				return fail("archive_decompression_quota_exceeded", err)
			}
			return err
		}
	}
	if header, err := tarReader.Next(); err != io.EOF || header != nil {
		if limitedStream.N == 0 {
			return fail("archive_decompression_quota_exceeded", err)
		}
		if err == nil {
			err = fmt.Errorf("extra archive entry")
		}
		return fail("archive_extra_entry", err)
	}
	if limitedStream.N == 0 {
		return fail("archive_decompression_quota_exceeded", nil)
	}
	if total != manifest.UncompressedBytes || directories != manifest.DirectoryCount {
		return fail("archive_summary_mismatch", nil)
	}
	var trailing [1]byte
	if count, readErr := limitedStream.Read(trailing[:]); count != 0 || (readErr != nil && readErr != io.EOF) {
		if limitedStream.N == 0 {
			return fail("archive_decompression_quota_exceeded", readErr)
		}
		return fail("archive_trailing_tar_data", readErr)
	}
	if _, peekErr := buffered.Peek(1); peekErr == nil {
		return fail("archive_concatenated_or_trailing_data", nil)
	} else if peekErr != io.EOF {
		return fail("archive_trailing_data_check_failed", peekErr)
	}
	if destination != "" {
		return syncExtractedDirectories(destination, manifest)
	}
	return nil
}

func archiveDecompressionLimit(manifest *Manifest, limits Limits) int64 {
	limits = NormalizeLimits(limits)
	perEntryAllowance := int64(limits.MaxPathBytes) + 8*1024
	metadataAllowance := saturatingMultiply(manifest.EntryCount+1, perEntryAllowance)
	metadataAllowance = saturatingAdd(metadataAllowance, 1024*1024)

	contentBudget := saturatingAdd(manifest.UncompressedBytes, metadataAllowance)
	ratioBudget := saturatingAdd(
		int64(float64(manifest.ArchiveBytes)*limits.MaxExpansionRatio),
		metadataAllowance,
	)
	if ratioBudget < contentBudget {
		contentBudget = ratioBudget
	}
	if contentBudget >= maximumInt64 {
		return maximumInt64 - 1
	}
	return contentBudget
}

func saturatingAdd(left, right int64) int64 {
	if left < 0 || right < 0 || left > maximumInt64-right {
		return maximumInt64
	}
	return left + right
}

func saturatingMultiply(left, right int64) int64 {
	if left < 0 || right < 0 || (right != 0 && left > maximumInt64/right) {
		return maximumInt64
	}
	return left * right
}

func normalizeArchiveHeader(header *tar.Header, limits Limits) (string, bool, error) {
	if header == nil || header.Linkname != "" {
		return "", false, fail("archive_header_invalid", nil)
	}
	directory := header.Typeflag == tar.TypeDir
	if !directory && header.Typeflag != tar.TypeReg && header.Typeflag != tar.TypeRegA {
		return "", false, fail("archive_entry_type_forbidden", nil)
	}
	for key := range header.PAXRecords {
		if key != "path" || strings.Contains(strings.ToLower(key), "sparse") {
			return "", false, fail("archive_pax_metadata_forbidden", nil)
		}
	}
	name := header.Name
	if directory {
		if !strings.HasSuffix(name, "/") || strings.HasSuffix(name, "//") {
			return "", false, fail("archive_directory_name_invalid", nil)
		}
		name = strings.TrimSuffix(name, "/")
	}
	clean, err := ValidateRelativePath(name, limits)
	if err != nil || clean != name {
		return "", false, fail("archive_entry_path_invalid", err)
	}
	if header.Size < 0 || (directory && header.Size != 0) {
		return "", false, fail("archive_entry_size_invalid", nil)
	}
	return clean, directory, nil
}

func extractDirectory(root, relative string) error {
	path := filepath.Join(root, filepath.FromSlash(relative))
	if err := os.Mkdir(path, 0o700); err != nil {
		return fail("archive_directory_create_failed", err)
	}
	return nil
}

func consumeArchiveFile(reader io.Reader, root, relative string, expected ManifestEntry) error {
	hasher := sha256.New()
	var destination io.Writer = hasher
	var file *os.File
	if root != "" {
		path := filepath.Join(root, filepath.FromSlash(relative))
		parentInfo, err := os.Lstat(filepath.Dir(path))
		if err != nil || unsafeFileInfo(parentInfo) || !parentInfo.IsDir() {
			return fail("archive_parent_directory_invalid", err)
		}
		file, err = os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
		if err != nil {
			return fail("archive_file_create_failed", err)
		}
		destination = io.MultiWriter(file, hasher)
	}
	written, copyErr := io.Copy(destination, reader)
	if file != nil {
		if copyErr == nil {
			copyErr = file.Sync()
		}
		closeErr := file.Close()
		if copyErr == nil {
			copyErr = closeErr
		}
	}
	if copyErr != nil || written != expected.Size {
		return fail("archive_file_truncated", copyErr)
	}
	if hex.EncodeToString(hasher.Sum(nil)) != expected.SHA256 {
		return fail("archive_file_digest_mismatch", nil)
	}
	return nil
}

func syncExtractedDirectories(root string, manifest *Manifest) error {
	directories := []string{root}
	for _, entry := range manifest.Entries {
		if entry.Type == "directory" {
			directories = append(directories, filepath.Join(root, filepath.FromSlash(entry.Path)))
		}
	}
	sort.Slice(directories, func(i, j int) bool { return len(directories[i]) > len(directories[j]) })
	for _, directory := range directories {
		if err := syncDirectory(directory); err != nil {
			return fail("archive_directory_sync_failed", err)
		}
	}
	return nil
}

func verifyTree(ctx context.Context, root string, manifest *Manifest, allowAbsent bool, limits Limits) error {
	exists, err := pathExists(root)
	if err != nil {
		return fail("installed_tree_unreadable", err)
	}
	if !exists {
		if allowAbsent && manifest.SourceWorldState == "absent" {
			return nil
		}
		return fail("installed_tree_missing", nil)
	}
	if allowAbsent && manifest.SourceWorldState == "absent" {
		return fail("installed_tree_expected_absent", nil)
	}
	entries, _, _, _, err := inspectSourceTree(ctx, root, limits)
	if err != nil {
		return err
	}
	if len(entries) != len(manifest.Entries) {
		return fail("installed_tree_entry_mismatch", nil)
	}
	for position, source := range entries {
		expected := manifest.Entries[position]
		if source.path != expected.Path || source.directory != (expected.Type == "directory") || source.size != expected.Size {
			return fail("installed_tree_entry_mismatch", nil)
		}
		if source.directory {
			continue
		}
		file, err := openRegularNoFollow(source.fullPath)
		if err != nil {
			return fail("installed_tree_file_open_failed", err)
		}
		hasher := sha256.New()
		written, copyErr := io.Copy(hasher, io.LimitReader(file, limits.MaxFileBytes+1))
		closeErr := file.Close()
		if copyErr != nil || closeErr != nil || written != expected.Size || hex.EncodeToString(hasher.Sum(nil)) != expected.SHA256 {
			return fail("installed_tree_file_mismatch", copyErr)
		}
	}
	return nil
}
