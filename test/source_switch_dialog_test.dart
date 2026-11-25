import 'package:duanju_app/models.dart';
import 'package:duanju_app/source_switch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('source switch dialog hides restricted tier by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSourceSwitchDialog(
                context,
                sources: const [
                  SourceSite.hongguo,
                  SourceSite.huangdou,
                  SourceSite.huangguoai,
                ],
                current: SourceSite.hongguo,
                allSources: false,
                onSelected: (_, {required bool allSources}) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('限制级 2'), findsNothing);
    expect(find.text('绿色 1'), findsNothing);
    expect(find.text('红果'), findsOneWidget);
    expect(find.text('黄豆'), findsNothing);
  });

  testWidgets('source switch dialog filters green and restricted tiers', (
    tester,
  ) async {
  final picks = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showSourceSwitchDialog(
              context,
              sources: const [
                SourceSite.hongguo,
                SourceSite.huangdou,
                SourceSite.huangguoai,
              ],
              current: SourceSite.hongguo,
              allSources: false,
              showRestricted: true,
              onSelected: (source, {required bool allSources}) {
                picks.add('${source.id}:$allSources');
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  expect(find.text('切换站源'), findsOneWidget);
  expect(find.text('红果'), findsOneWidget);
  expect(find.text('黄豆'), findsNothing);

  await tester.tap(find.text('限制级 2'));
  await tester.pumpAndSettle();
  expect(find.text('黄豆'), findsOneWidget);
  expect(find.text('AI'), findsOneWidget);
  expect(find.text('红果'), findsNothing);

  await tester.tap(find.text('AI'));
  await tester.pumpAndSettle();
  expect(picks, ['huangguoai:false']);
  });

  testWidgets('source switch dialog highlights all-sources aggregate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSourceSwitchDialog(
                context,
                sources: const [SourceSite.hongguo, SourceSite.fanqie],
                current: SourceSite.hongguo,
                allSources: true,
                onSelected: (_, {required bool allSources}) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('全部站源'), findsOneWidget);
    expect(find.text('当前：全部站源'), findsOneWidget);
  });

  test('restricted sources stay off by default', () async {
    expect(SourceSite.isRestricted('huangdou'), isTrue);
    expect(SourceSite.isRestricted('miguo'), isFalse);
    expect(SourceSite.isRestricted('hongguo'), isFalse);
  });
}