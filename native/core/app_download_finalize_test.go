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
			ID: id, Index: 1, Drama: nativeDrama{ID: "hongguo:70002", Source: "hongguo", Title: "封装测试"},
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
	folder := nativePublishedShowFolder(record.Drama)
	dir := filepath.Join(engine.downloads.root, folder)
	info, err := os.Stat(filepath.Join(dir, "001.mp4"))
	if err != nil {
		t.Fatal(err)
	}
	if record.File != "001.mp4" || record.Folder != folder || record.Key != "" || record.Bytes != info.Size() {
		t.Fatalf("record: %+v", record)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "001.mp4" {
		t.Fatalf("leftover files: %+v", entries)
	}
	if _, err := os.Stat(filepath.Join(engine.downloads.root, id)); !os.IsNotExist(err) {
		t.Fatal("hash job directory was not replaced by the visible show folder")
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

func TestFinalizeStreamDownloadSucceedsDuringMediaLease(t *testing.T) {
	engine, id := hlsStreamFixture(t)
	if _, err := engine.workLease("media", "start"); err != nil {
		t.Fatal(err)
	}
	defer func() { _, _ = engine.workLease("media", "end") }()
	if err := engine.downloads.finalizeStreamDownload(id); err != nil {
		t.Fatal(err)
	}
	record := engine.downloads.jobs[id]
	if record.File != "001.mp4" {
		t.Fatalf("record: %+v", record)
	}
}

func TestPublishedEpisodesShareShowFolderAndRemoveKeepsSiblings(t *testing.T) {
	engine, first := hlsStreamFixture(t)
	second := nativeDownloadID("hongguo:70002", 2)
	dir := filepath.Join(engine.downloads.root, second)
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "index.m3u8"), []byte("#EXTM3U\n#EXT-X-ENDLIST\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "media.mp4"), []byte("second-episode-mp4"), 0600); err != nil {
		t.Fatal(err)
	}
	engine.downloads.jobs[second] = &nativeDownloadRecord{
		nativeDownloadJob: nativeDownloadJob{
			ID: second, Index: 2, Drama: engine.downloads.jobs[first].Drama,
			State: "completed", Bytes: 18,
		},
		File: "index.m3u8",
	}
	if err := engine.downloads.finalizeStreamDownload(first); err != nil {
		t.Fatal(err)
	}
	if err := engine.downloads.finalizeStreamDownload(second); err != nil {
		t.Fatal(err)
	}
	folder := nativePublishedShowFolder(engine.downloads.jobs[first].Drama)
	show := filepath.Join(engine.downloads.root, folder)
	if _, err := os.Stat(filepath.Join(show, "001.mp4")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(show, "002.mp4")); err != nil {
		t.Fatal(err)
	}
	if err := engine.downloads.control(first, "remove"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(show, "001.mp4")); !os.IsNotExist(err) {
		t.Fatal("removed episode still present")
	}
	body, err := os.ReadFile(filepath.Join(show, "002.mp4"))
	if err != nil || string(body) != "second-episode-mp4" {
		t.Fatalf("sibling episode lost: %v", err)
	}
}