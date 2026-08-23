package worldstore

import (
	"archive/tar"
	"strings"
	"testing"
)

func TestPortablePathPolicyRejectsTraversalWindowsAliasesAndCollisions(t *testing.T) {
	limits := DefaultLimits()
	unsafe := []string{
		"", "../world", "/world", "//server/share", `\\server\share`, "C:/world",
		`world\region`, "world:stream", "world//region", "world/.", "world/..",
		"world/CON", "world/com1.dat", "world/region.", "world/region ",
		"world/region*", "world/region?", "world/世界",
	}
	for _, value := range unsafe {
		if _, err := ValidateRelativePath(value, limits); err == nil {
			t.Errorf("ValidateRelativePath(%q) unexpectedly succeeded", value)
		}
	}
	if value, err := ValidateRelativePath("world/DIM-1/region", limits); err != nil || value != "world/DIM-1/region" {
		t.Fatalf("portable path rejected: value=%q err=%v", value, err)
	}

	caseIndex := newCollisionIndex()
	if err := caseIndex.Add("Region", true); err != nil {
		t.Fatal(err)
	}
	if err := caseIndex.Add("region", true); Code(err) != "archive_case_collision" {
		t.Fatalf("expected case collision, got %v", err)
	}

	prefixIndex := newCollisionIndex()
	if err := prefixIndex.Add("region", false); err != nil {
		t.Fatal(err)
	}
	if err := prefixIndex.Add("region/r.0.0.mca", false); Code(err) != "archive_prefix_collision" {
		t.Fatalf("expected prefix collision, got %v", err)
	}
}

func TestArchiveHeaderPolicyRejectsLinksSparseMetadataAndNonPortableNames(t *testing.T) {
	limits := DefaultLimits()
	cases := []tar.Header{
		{Name: "../level.dat", Typeflag: tar.TypeReg},
		{Name: "/level.dat", Typeflag: tar.TypeReg},
		{Name: `world\level.dat`, Typeflag: tar.TypeReg},
		{Name: "world:stream", Typeflag: tar.TypeReg},
		{Name: "link", Typeflag: tar.TypeSymlink, Linkname: "/etc/passwd"},
		{Name: "hard", Typeflag: tar.TypeLink, Linkname: "level.dat"},
		{Name: "fifo", Typeflag: tar.TypeFifo},
		{Name: "device", Typeflag: tar.TypeChar},
		{Name: "sparse", Typeflag: tar.TypeReg, PAXRecords: map[string]string{"GNU.sparse.map": "0,1"}},
		{Name: "duplicate/", Typeflag: tar.TypeDir, Size: 1},
	}
	for _, header := range cases {
		header := header
		if _, _, err := normalizeArchiveHeader(&header, limits); err == nil {
			t.Errorf("unsafe header unexpectedly accepted: name=%q type=%d", header.Name, header.Typeflag)
		}
	}

	deep := strings.Repeat("a/", limits.MaxDepth) + "level.dat"
	if _, _, err := normalizeArchiveHeader(&tar.Header{Name: deep, Typeflag: tar.TypeReg}, limits); err == nil {
		t.Fatal("archive depth bomb unexpectedly accepted")
	}
}
