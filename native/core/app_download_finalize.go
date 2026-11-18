package core

import (
	"errors"
	"os"
	"path/filepath"
)

func nativeDownloadJobIDValid(id string) bool {
	if len(id) != 32 {
		return false
	}
	for _, r := range id {
		if (r < '0' || r > '9') && (r < 'a' || r > 'f') {
			return false
		}
	}
	return true
}

func (manager *nativeDownloads) finalizeStreamDownload(id string) error {
	if !nativeDownloadJobIDValid(id) {
		return errors.New("下载任务无效")
	}
	manager.mu.Lock()
	defer manager.mu.Unlock()
	if manager.loadErr != nil {
		return manager.loadErr
	}
	if manager.closed || manager.moving {
		return errors.New("下载目录正在迁移或队列已关闭，请稍后重试")
	}
	record := manager.jobs[id]
	if record == nil {
		return errors.New("下载任务不存在，请刷新列表")
	}
	if record.State != "completed" || record.File != "index.m3u8" {
		return errors.New("只能替换已完成的流文件下载")
	}
	directory := manager.jobDirectory(record.nativeDownloadJob)
	mp4 := filepath.Join(directory, "media.mp4")
	info, err := os.Stat(mp4)
	if err != nil || !info.Mode().IsRegular() || info.Size() <= 0 {
		return errors.New("未找到有效的 media.mp4，请先完成封装")
	}
	record.File = "media.mp4"
	record.Key = ""
	record.Bytes = info.Size()
	record.Total = info.Size()
	record.Revision++
	if err := manager.publishCompletedLocked(record); err != nil {
		record.File = "index.m3u8"
		return err
	}
	return manager.saveLocked()
}