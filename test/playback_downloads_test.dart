import 'dart:async';

import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_downloads.dart';
import 'package:duanju_app/player_menu.dart';
import 'package:duanju_app/remote_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class ReceiptRepository extends FixtureRepository {
  List<DownloadJob> jobs = [];
  Completer<List<DownloadJob>>? pending;
  bool failPoll = false;
  int polls = 0;
  @override
  bool get supportsDownloads => true;
  @override
  Future<List<DownloadJob>> downloads() async {
    polls++;
    if (failPoll) throw StateError('transient poll error');
    return pending?.future ?? jobs;
  }
}

Episode episode(int number, {String id = ''}) => Episode({
  'id': id,
  'currentEpisode': number,
  'videoUrl': 'https://synthetic.invalid/expired?signature=old',
}, number);

DownloadJob job(
  int number, {
  String state = 'completed',
  Drama? drama,
  bool archived = false,
}) => DownloadJob(
  id: '${drama?.id ?? FixtureRepository.free.id}:$number',
  drama: drama ?? FixtureRepository.free,
  episode: episode(number), // legacy jobs need not have a chapter ID
  state: state,
  archived: archived,
);

void main() {
  testWidgets(
    'persisted per-series receipts survive reopening; delete clears live badges',
    (tester) async {
      const otherTitle = Drama(
        id: 'hongguo:101',
        source: 'hongguo',
        title: '第二季',
      );
      const otherSource = Drama(
        id: 'fanqie:100',
        source: 'fanqie',
        title: '测试短剧',
      );
      final repository = ReceiptRepository()
        ..jobs = [
          job(1, archived: true),
          job(2, state: 'downloading'),
          job(3, state: 'queued'),
          job(4, state: 'paused'),
          job(5, state: 'failed'),
          job(2, drama: otherTitle),
          job(3, drama: otherSource),
        ];
      var receipts = PlaybackDownloads(repository, FixtureRepository.free);
      await tester.pump();
      expect(receipts.completed, {1});
      receipts.dispose();
      receipts = PlaybackDownloads(repository, FixtureRepository.free);
      await tester.pump();
      expect(receipts.completed, {1});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: receipts,
              builder: (_, _) => PlayerEpisodeGrid(
                episodes: [
                  episode(1, id: 'new-chapter-id'),
                  episode(2),
                ],
                currentIndex: 0,
                downloadedNumbers: receipts.completed,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('已下载'), findsOneWidget);
      final selected = tester.widget<RemoteEpisodeButton>(
        find.byKey(const ValueKey('play-episode-1')),
      );
      expect(selected.current, isTrue);
      expect(selected.downloaded, isTrue);
      expect(
        tester
            .widget<RemoteEpisodeButton>(
              find.byKey(const ValueKey('play-episode-2')),
            )
            .downloaded,
        isFalse,
      );

      // Downloads removal changes the authoritative list while playback is open.
      repository.jobs.removeAt(0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('已下载'), findsNothing);
      expect(receipts.completed, isEmpty);
      // A subsequent download completion is visible without reopening playback.
      repository.jobs.add(job(2));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(receipts.completed, {2});
      expect(find.text('已下载'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      receipts.dispose();
    },
  );

  testWidgets(
    'polls do not overlap; failure/dispose never fabricate deletion',
    (tester) async {
      final repository = ReceiptRepository()..pending = Completer();
      final receipts = PlaybackDownloads(repository, FixtureRepository.free);
      await receipts.refresh();
      await tester.pump(const Duration(seconds: 4));
      expect(repository.polls, 1);
      repository.pending!.complete([job(1)]);
      await tester.pump();
      expect(receipts.completed, {1});
      repository.pending = null;
      repository.failPoll = true;
      await receipts.refresh();
      expect(receipts.completed, {1});
      repository.failPoll = false;
      repository.pending = Completer();
      final refresh = receipts.refresh();
      receipts.dispose();
      repository.pending!.complete([]);
      await refresh;
      expect(receipts.completed, {1});
    },
  );

  testWidgets('access revoked during poll clears receipts', (tester) async {
    var allowed = true;
    final repository = ReceiptRepository()..jobs = [job(1)];
    final receipts = PlaybackDownloads(
      repository,
      FixtureRepository.free,
      allowed: () => allowed,
    );
    await tester.pump();
    expect(receipts.completed, {1});
    allowed = false;
    await receipts.refresh();
    expect(receipts.completed, isEmpty);
    receipts.dispose();
  });

  for (final (compact, textScale) in [
    (false, 1.0),
    (true, 1.0),
    (false, 1.5),
    (true, 1.5),
  ]) {
    testWidgets(
      'episode label fits ${compact ? 'compact' : 'standard'} grid at $textScale and stays selectable',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        int? picked;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerEpisodeGrid(
                episodes: [for (var i = 1; i <= 12; i++) episode(i)],
                currentIndex: 0,
                compact: compact,
                downloadedNumbers: const {1, 2},
                onSelected: (index) => picked = index,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('已下载'), findsNWidgets(2));
        await tester.tap(find.byKey(const ValueKey('play-episode-2')));
        expect(picked, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
