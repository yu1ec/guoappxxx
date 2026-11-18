package core

import (
	"os"
	"path/filepath"
	"testing"
)

func hlsStreamFixture(t *testing.T) (*nativeEngine, string) {
	t.Helper()
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	id := nativeDownloadID("hongguo:70002", 1)
	manager := engine.downloads
	dir := filepath.Join(manager.root, id)
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "index.m3u8"), []byte("#EXTM3U\n#EXT-X-ENDLIST\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "seg.ts"), []byte("segment"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "media.mp4"), []byte("synthetic-mp4-content"), 0600); err != nil {
		t.Fatal(err)
	}
	manager.jobs[id] = &nativeDownloadRecord{
		nativeDownloadJob: nativeDownloadJob{
			ID: id, Index: 1, Drama: nativeDrama{ID: "hongguo:70002", Source: "hongguo"},
			State: "completed", Bytes: 20,
		},
		File: "index.m3u8",
	}
	if err := manager.saveLocked(); err != nil {
		t.Fatal(err)
	}
	return engine, id
}

func TestFinalizeStreamDownloadReplacesHLSWithMp4(t *testing.T) {
	engine, id := hlsStreamFixture(t)
	if err := engine.downloads.finalizeStreamDownload(id); err != nil {
		t.Fatal(err)
	}
	record := engine.downloads.jobs[id]
	dir := filepath.Join(engine.downloads.root, id)
	info, err := os.Stat(filepath.Join(dir, "media.mp4"))
	if err != nil {
		t.Fatal(err)
	}
	if record.File != "media.mp4" || record.Key != "" || record.Bytes != info.Size() {
		t.Fatalf("record: %+v", record)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "media.mp4" {
		t.Fatalf("leftover files: %+v", entries)
	}
}

func TestFinalizeStreamDownloadRejectsMissingMp4(t *testing.T) {
	engine, id := hlsStreamFixture(t)
	dir := filepath.Join(engine.downloads.root, id)
	if err := os.Remove(filepath.Join(dir, "media.mp4")); err != nil {
		t.Fatal(err)
	}
	if err := engine.downloads.finalizeStreamDownload(id); err == nil {
		t.Fatal("expected missing mp4 error")
	}
}

func TestFinalizeStreamDownloadRejectsNonHLS(t *testing.T) {
	engine, id := storageFixture(t)
	if err := engine.downloads.finalizeStreamDownload(id); err == nil {
		t.Fatal("expected non-hls rejection")
	}
}

func TestFinalizeStreamDownloadRejectsWhileMediaBusy(t *testing.T) {
	engine, id := hlsStreamFixture(t)
	if _, err := engine.workLease("media", "start"); err != nil {
		t.Fatal(err)
	}
	defer func() { _, _ = engine.workLease("media", "end") }()
	if err := engine.downloads.finalizeStreamDownload(id); err == nil {
		t.Fatal("expected media busy rejection")
	}
}