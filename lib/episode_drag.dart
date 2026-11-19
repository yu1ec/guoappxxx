import 'dart:math' as math;

/// 将手指竖直位移转成切集进度（上滑为正 / 下一集）。
double episodeDragProgress({
  required double deltaY,
  required double viewHeight,
  required bool canSwipeNext,
  required bool canSwipePrev,
}) {
  if (viewHeight <= 0) return 0;
  var progress = deltaY / viewHeight;
  if (progress > 0 && !canSwipeNext) {
    progress = _rubberBand(progress);
  } else if (progress < 0 && !canSwipePrev) {
    progress = -_rubberBand(-progress);
  }
  return progress.clamp(-1.0, 1.0);
}

double _rubberBand(double overscroll) => overscroll * 0.35;

/// 抬手时是否达到切集阈值；[deltaY] 与 [episodeDragProgress] 同向（上滑为正）。
bool episodeSwipeShouldCommit({
  required double deltaY,
  required double threshold,
}) =>
    deltaY.abs() >= threshold;

/// 达到阈值时的切集方向：1 下一集，-1 上一集；未达标返回 null。
int? episodeSwipeDirection({
  required double deltaY,
  required double threshold,
}) {
  if (!episodeSwipeShouldCommit(deltaY: deltaY, threshold: threshold)) {
    return null;
  }
  return deltaY > 0 ? 1 : -1;
}

/// 播完判定：接近片尾即视为正常结束，避免误进 early_completion。
bool playbackReachedNaturalEnd({
  required Duration position,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return false;
  if (position >= duration - const Duration(seconds: 2)) return true;
  final ratio = position.inMilliseconds / math.max(duration.inMilliseconds, 1);
  return ratio >= 0.97;
}