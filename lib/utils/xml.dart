/// Re-indents XML text.
String prettyXml(String s) {
  final sb = StringBuffer();
  var depth = 0;
  final tokens = RegExp(r'<[^>]+>|[^<]+')
      .allMatches(s.trim().replaceAll(RegExp(r'>\s+<'), '><'))
      .map((m) => m.group(0)!)
      .toList();
  for (final t in tokens) {
    if (t.startsWith('</')) {
      depth = depth - 1 < 0 ? 0 : depth - 1;
      sb
        ..write('  ' * depth)
        ..write(t)
        ..write('\n');
    } else if (t.startsWith('<') &&
        !t.startsWith('<?') &&
        !t.startsWith('<!') &&
        !t.endsWith('/>')) {
      sb
        ..write('  ' * depth)
        ..write(t)
        ..write('\n');
      depth++;
    } else {
      sb
        ..write('  ' * depth)
        ..write(t.trim())
        ..write('\n');
    }
  }
  // Join "<a>text</a>" onto one line.
  return sb
      .toString()
      .replaceAllMapped(
        RegExp(r'(<[^/!?][^>]*[^/]>)\n\s*([^<\n]+)\n\s*(</[^>]+>)'),
        (m) => '${m[1]}${m[2]}${m[3]}',
      )
      .trimRight();
}
