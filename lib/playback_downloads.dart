import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core_bridge.dart';
import 'models.dart';

/// A live projection of persisted download receipts, not a second local cache.
///
/// Match the native queue's identity: source-qualified series ID + episode
/// number. Providers give separate series IDs to seasons; neither titles nor
/// signed/expiring media URLs are identities. This also recognizes legacy jobs
/// whose chapter IDs were absent or have changed after refreshing a source.
class PlaybackDownloads extends ChangeNotifier {
  PlaybackDownloads(this.repository, this.drama, {this.allowed}) {
    unawaited(refresh());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  final AppRepository repository;
  final Drama drama;
  final bool Function()? allowed;
  Timer? _timer;
  bool _disposed = false;
  bool _refreshing = false;
  Set<int> _completed = const {};
  Set<int> get completed => _completed;

  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      final jobs = repository.supportsDownloads && (allowed?.call() ?? true)
          ? await repository.downloads()
          : const <DownloadJob>[];
      if (_disposed) return;
      final completed = (allowed?.call() ?? true)
          ? jobs
                .where(
                  (job) =>
                      job.completed &&
                      job.drama.id == drama.id &&
                      job.drama.source == drama.source,
                )
                .map((job) => job.episode.number)
                .toSet()
          : <int>{};
      if (!setEquals(completed, _completed)) {
        _completed = Set.unmodifiable(completed);
        notifyListeners();
      }
    } catch (_) {
      // A transient core/poll error is not proof the user deleted a receipt.
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
