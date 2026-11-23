package core

import (
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
)

// Reserve the only worker slot: these tests exercise the real persisted queue
// without contacting a provider or downloading video.
func holdReceiptWorker(manager *nativeDownloads) {
	manager.concurrency = 1
	manager.active["receipt-test-worker"] = func() {}
}

func TestDownloadReceiptsMixedBatchAndConcurrentEnqueue(t *testing.T) {
	manager := downloadTestManager(t)
	holdReceiptWorker(manager)
	input := downloadTestInput(5)
	if n, err := manager.enqueue(input); err != nil || n != 5 {
		t.Fatalf("seed: %d %v", n, err)
	}
	manager.mu.Lock()
	for i, state := range []string{"completed", "queued", "downloading", "paused", "failed"} {
		manager.jobs[nativeDownloadID(input.Drama.ID, i+1)].State = state
	}
	manager.mu.Unlock()
	mixed := downloadTestInput(6)
	mixed.Entries = append(mixed.Entries, mixed.Entries[5])
	// A changed URL/chapter ID or requested quality must not bypass the receipt.
	mixed.Entries[0].Chapter.ID = "refreshed-chapter-id"
	mixed.Entries[0].Chapter.VideoURL = "https://synthetic.invalid/signed?token=new"
	mixed.Quality = 720
	if n, err := manager.enqueue(mixed); err != nil || n != 1 {
		t.Fatalf("mixed: %d %v", n, err)
	}
	for i, state := range []string{"completed", "queued", "downloading", "paused", "failed"} {
		if got := manager.jobs[nativeDownloadID(input.Drama.ID, i+1)].State; got != state {
			t.Fatalf("episode %d: %s", i+1, got)
		}
	}
	var added atomic.Int32
	var wg sync.WaitGroup
	concurrent := downloadTestInput(7)
	for range 24 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			n, err := manager.enqueue(concurrent)
			if err != nil {
				t.Error(err)
			}
			added.Add(int32(n))
		}()
	}
	wg.Wait()
	if added.Load() != 1 || len(manager.jobs) != 7 {
		t.Fatalf("duplicate concurrent work: added=%d jobs=%d", added.Load(), len(manager.jobs))
	}
	// Collection updates still retry failures, but not paused/queued/completed.
	concurrent.Force = true
	if n, err := manager.enqueue(concurrent); err != nil || n != 1 {
		t.Fatalf("retry failure: %d %v", n, err)
	}
	if manager.jobs[nativeDownloadID(input.Drama.ID, 1)].State != "completed" || manager.jobs[nativeDownloadID(input.Drama.ID, 4)].State != "paused" {
		t.Fatal("retry changed protected state")
	}
}

func TestDownloadReceiptSurvivesRestartArchiveAndMissingFileUntilDelete(t *testing.T) {
	manager := downloadTestManager(t)
	holdReceiptWorker(manager)
	input := downloadTestInput(1)
	if _, err := manager.enqueue(input); err != nil {
		t.Fatal(err)
	}
	id := nativeDownloadID(input.Drama.ID, 1)
	manager.mu.Lock()
	record := manager.jobs[id]
	record.State, record.File, record.Progress = "completed", "1.mp4", 1
	record.Chapter.ID = "" // legacy receipt without a provider chapter ID
	directory := manager.jobDirectory(record.nativeDownloadJob)
	if err := os.MkdirAll(directory, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, record.File), []byte("synthetic media"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := manager.saveLocked(); err != nil {
		t.Fatal(err)
	}
	manager.mu.Unlock()
	if err := manager.control(id, "archive"); err != nil {
		t.Fatal(err)
	}
	manager.close()
	reopened := newNativeDownloads(manager.engine)
	t.Cleanup(reopened.close)
	holdReceiptWorker(reopened)
	jobs, err := reopened.snapshot()
	if err != nil || len(jobs) != 1 || jobs[0].State != "completed" || !jobs[0].Archived {
		t.Fatalf("restart lost receipt: %+v %v", jobs, err)
	}
	if err := os.Remove(filepath.Join(directory, "1.mp4")); err != nil {
		t.Fatal(err)
	}
	if _, found, err := reopened.localPlan(input.Drama.ID, 1); !found || err != errNativeLocalFile {
		t.Fatalf("missing local file should report error without dropping receipt: %v %v", found, err)
	}
	for _, force := range []bool{false, true} {
		input.Force = force
		if n, err := reopened.enqueue(input); err != nil || n != 0 {
			t.Fatalf("missing file bypassed receipt (force=%v): %d %v", force, n, err)
		}
	}
	if err := reopened.control(id, "resume"); err != nil {
		t.Fatal(err)
	}
	if reopened.jobs[id].State != "completed" || !reopened.jobs[id].Archived {
		t.Fatal("completed receipt reset")
	}
	if err := reopened.control(id, "remove"); err != nil {
		t.Fatal(err)
	}
	if jobs, err := reopened.snapshot(); err != nil || len(jobs) != 0 {
		t.Fatalf("delete retained marker: %+v %v", jobs, err)
	}
	if n, err := reopened.enqueue(input); err != nil || n != 1 {
		t.Fatalf("explicit deletion must permit download: %d %v", n, err)
	}
}

func TestDownloadReceiptSeriesSeasonAndSourceIsolation(t *testing.T) {
	manager := downloadTestManager(t)
	holdReceiptWorker(manager)
	for _, drama := range []nativeDrama{
		{ID: "hongguo:100", Source: "hongguo", Title: "同名剧 第一季"},
		{ID: "hongguo:101", Source: "hongguo", Title: "同名剧 第二季"},
		{ID: "fanqie:100", Source: "fanqie", Title: "同名剧 第一季"},
	} {
		input := downloadTestInput(1)
		input.Drama = drama
		if n, err := manager.enqueue(input); err != nil || n != 1 {
			t.Fatalf("isolated series: %d %v", n, err)
		}
	}
	if len(manager.jobs) != 3 {
		t.Fatal("unrelated episodes conflated")
	}
}

func TestDownloadReceiptLegacyMissingFileState(t *testing.T) {
	manager := downloadTestManager(t)
	holdReceiptWorker(manager)
	input := downloadTestInput(1)
	if _, err := manager.enqueue(input); err != nil {
		t.Fatal(err)
	}
	record := manager.jobs[nativeDownloadID(input.Drama.ID, 1)]
	// This exact legacy state was written by localPlan after a completed file
	// went missing. Ordinary failed downloads must remain retryable.
	record.State, record.File, record.Error = "failed", "1.mp4", "本地文件缺失，请重新下载"
	manager.close()
	reopened := newNativeDownloads(manager.engine)
	t.Cleanup(reopened.close)
	holdReceiptWorker(reopened)
	jobs, err := reopened.snapshot()
	if err != nil || len(jobs) != 1 || jobs[0].State != "completed" {
		t.Fatalf("legacy receipt lost: %+v %v", jobs, err)
	}
	input.Force = true
	if n, err := reopened.enqueue(input); err != nil || n != 0 {
		t.Fatalf("legacy receipt bypassed: %d %v", n, err)
	}
}
