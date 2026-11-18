package core

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unicode"
)

func nativeSafeDownloadName(name string) string {
	var builder strings.Builder
	for _, r := range name {
		if r < 32 || strings.ContainsRune(`<>:"/\|?*`, r) {
			builder.WriteByte('_')
			continue
		}
		builder.WriteRune(r)
	}
	result := strings.TrimRight(strings.TrimSpace(builder.String()), ". ")
	runes := []rune(result)
	if len(runes) > 60 {
		result = strings.TrimRight(string(runes[:60]), ". ")
	}
	if result == "" {
		return "短剧"
	}
	return result
}

func nativeDownloadNameAllowed(name string) bool {
	if name == "" || name == "." || name == ".." {
		return false
	}
	runes := []rune(name)
	if len(runes) > 120 {
		return false
	}
	for _, r := range runes {
		if r < 32 || strings.ContainsRune(`<>:"/\|?*`, r) {
			return false
		}
	}
	return !strings.HasSuffix(name, ".") && !strings.HasSuffix(name, " ")
}

func nativePublishedMp4Name(name string) bool {
	stem, ok := strings.CutSuffix(name, ".mp4")
	if !ok || stem == "" || len(stem) > 6 {
		return false
	}
	for _, r := range stem {
		if !unicode.IsDigit(r) {
			return false
		}
	}
	n, err := strconv.Atoi(stem)
	return err == nil && n >= 1 && n <= 100000
}

func nativeDownloadFileNameValid(name string) bool {
	return name == "media.mp4" || name == "index.m3u8" || nativePublishedMp4Name(name)
}

func nativeDownloadFolderValid(folder, source, id string) bool {
	if folder == "" || folder == source+"/"+id {
		return true
	}
	if filepath.ToSlash(folder) != folder || strings.Contains(folder, "/") {
		return false
	}
	return nativeDownloadNameAllowed(folder)
}

func nativePublishedShowFolder(drama nativeDrama) string {
	sum := sha256.Sum256([]byte(drama.ID))
	return nativeSafeDownloadName(drama.Title) + " [" + nativeSafeDownloadName(drama.Source) + "-" + hex.EncodeToString(sum[:6]) + "]"
}

func nativePublishedEpisodeName(index int) string {
	return fmt.Sprintf("%03d.mp4", index)
}

func (manager *nativeDownloads) dedicatedJobDirectory(job nativeDownloadJob) bool {
	return job.Folder == "" || job.Folder == job.Drama.Source+"/"+job.ID
}

func (manager *nativeDownloads) removeJobFiles(record nativeDownloadRecord) error {
	directory := manager.jobDirectory(record.nativeDownloadJob)
	if manager.dedicatedJobDirectory(record.nativeDownloadJob) {
		return os.RemoveAll(directory)
	}
	if record.File != "" {
		if err := os.Remove(filepath.Join(directory, record.File)); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	entries, err := os.ReadDir(directory)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if len(entries) == 0 {
		return os.Remove(directory)
	}
	return nil
}

func nativeMoveFile(source, target string) error {
	if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
		return err
	}
	if filepath.Clean(source) == filepath.Clean(target) {
		_ = os.Chmod(target, 0644)
		return nil
	}
	if _, err := os.Stat(target); err == nil {
		if err := os.Remove(target); err != nil {
			return err
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	if err := os.Rename(source, target); err == nil {
		_ = os.Chmod(target, 0644)
		return nil
	}
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	output, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		return err
	}
	defer output.Close()
	if _, err := io.Copy(output, input); err != nil {
		return err
	}
	if err := output.Sync(); err != nil {
		return err
	}
	return os.Remove(source)
}

func (manager *nativeDownloads) publishCompletedLocked(record *nativeDownloadRecord) error {
	if record == nil || record.File != "media.mp4" {
		return nil
	}
	oldFolder, oldFile := record.Folder, record.File
	source := filepath.Join(manager.jobDirectory(record.nativeDownloadJob), record.File)
	info, err := os.Stat(source)
	if err != nil || !info.Mode().IsRegular() || info.Size() <= 0 {
		return errors.New("未找到已完成的视频文件")
	}
	folder := nativePublishedShowFolder(record.Drama)
	name := nativePublishedEpisodeName(record.Index)
	if !nativeDownloadFolderValid(folder, record.Drama.Source, record.ID) || !nativePublishedMp4Name(name) {
		return errors.New("无法生成可见的下载文件名")
	}
	oldDir := manager.jobDirectory(record.nativeDownloadJob)
	record.Folder, record.File = folder, name
	target := filepath.Join(manager.jobDirectory(record.nativeDownloadJob), record.File)
	if err := nativeMoveFile(source, target); err != nil {
		record.Folder, record.File = oldFolder, oldFile
		return errors.New("无法把视频放到下载目录，请检查存储空间和权限")
	}
	if filepath.Clean(oldDir) != filepath.Clean(filepath.Dir(target)) {
		_ = os.RemoveAll(oldDir)
	}
	record.Bytes, record.Total = info.Size(), info.Size()
	return nil
}

func (manager *nativeDownloads) exposeRoot() {
	rel, err := filepath.Rel(manager.engine.directory, manager.root)
	if err != nil || strings.HasPrefix(rel, "..") {
		_ = os.Chmod(manager.root, 0755)
	}
}
