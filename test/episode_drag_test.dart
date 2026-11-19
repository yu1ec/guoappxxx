import 'package:duanju_app/episode_drag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('episodeDragProgress follows finger direction', () {
    expect(
      episodeDragProgress(
        deltaY: 120,
        viewHeight: 400,
        canSwipeNext: true,
        canSwipePrev: true,
      ),
      0.3,
    );
    expect(
      episodeDragProgress(
        deltaY: -80,
        viewHeight: 400,
        canSwipeNext: true,
        canSwipePrev: true,
      ),
      -0.2,
    );
  });

  test('episodeDragProgress rubber bands on first/last episode', () {
    final blockedNext = episodeDragProgress(
      deltaY: 200,
      viewHeight: 400,
      canSwipeNext: false,
      canSwipePrev: true,
    );
    expect(blockedNext, lessThan(0.5));
    expect(blockedNext, greaterThan(0));

    final blockedPrev = episodeDragProgress(
      deltaY: -200,
      viewHeight: 400,
      canSwipeNext: true,
      canSwipePrev: false,
    );
    expect(blockedPrev, greaterThan(-0.5));
    expect(blockedPrev, lessThan(0));
  });

  test('episodeSwipeDirection respects threshold', () {
    expect(
      episodeSwipeDirection(deltaY: 50, threshold: 60),
      isNull,
    );
    expect(episodeSwipeDirection(deltaY: 64, threshold: 60), 1);
    expect(episodeSwipeDirection(deltaY: -70, threshold: 60), -1);
  });

  test('playbackReachedNaturalEnd accepts near-end completion', () {
    expect(
      playbackReachedNaturalEnd(
        position: const Duration(seconds: 58),
        duration: const Duration(seconds: 60),
      ),
      isTrue,
    );
    expect(
      playbackReachedNaturalEnd(
        position: const Duration(seconds: 59),
        duration: const Duration(seconds: 61),
      ),
      isTrue,
    );
    expect(
      playbackReachedNaturalEnd(
        position: const Duration(seconds: 20),
        duration: const Duration(seconds: 60),
      ),
      isFalse,
    );
  });
}