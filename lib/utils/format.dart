/// Human-readable byte count: `512 B`, `1.5 KB`, `2.25 MB`.
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${_fmt(bytes / 1024.0, 1)} KB';
  return '${_fmt(bytes / 1024.0 / 1024.0, 2)} MB';
}

// toStringAsFixed rounds slightly differently from half-up; close enough for display.
String _fmt(double v, int digits) => v.toStringAsFixed(digits);

/// Compact age of a timestamp: `now`, `12s`, `5m`, `3h`, `2d`.
String timeAgo(int timestampMs, {int? nowMs}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final s = (now - timestampMs) ~/ 1000;
  if (s < 5) return 'now';
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m';
  if (s < 86400) return '${s ~/ 3600}h';
  return '${s ~/ 86400}d';
}
