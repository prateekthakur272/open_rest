class DiffLine {
  final String op; // ' ', '-' or '+'
  final String text;
  const DiffLine(this.op, this.text);
  @override
  bool operator ==(Object other) =>
      other is DiffLine && other.op == op && other.text == text;
  @override
  int get hashCode => Object.hash(op, text);
}

/// Line-based diff.
class Diff {
  Diff._();

  /// Line diff (old -> new). Returns null when inputs are too large to diff cheaply.
  static List<DiffLine>? lines(List<String> a, List<String> b) {
    var s = 0;
    while (s < a.length && s < b.length && a[s] == b[s]) {
      s++;
    }
    var ea = a.length;
    var eb = b.length;
    while (ea > s && eb > s && a[ea - 1] == b[eb - 1]) {
      ea--;
      eb--;
    }
    final x = a.sublist(s, ea);
    final y = b.sublist(s, eb);
    if (x.length > 2500 || y.length > 2500) return null;
    final n = x.length;
    final m = y.length;
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = x[i] == y[j]
            ? dp[i + 1][j + 1] + 1
            : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }
    final out = <DiffLine>[];
    for (var i = 0; i < s; i++) {
      out.add(DiffLine(' ', a[i]));
    }
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (x[i] == y[j]) {
        out.add(DiffLine(' ', x[i]));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        out.add(DiffLine('-', x[i]));
        i++;
      } else {
        out.add(DiffLine('+', y[j]));
        j++;
      }
    }
    while (i < n) {
      out.add(DiffLine('-', x[i++]));
    }
    while (j < m) {
      out.add(DiffLine('+', y[j++]));
    }
    for (var k = ea; k < a.length; k++) {
      out.add(DiffLine(' ', a[k]));
    }
    return out;
  }
}
