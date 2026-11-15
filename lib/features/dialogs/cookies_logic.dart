import 'package:open_rest/core/http/http.dart';

/// Cookies of one domain, sorted by name then path.
class CookieGroup {
  const CookieGroup(this.domain, this.cookies);
  final String domain;
  final List<StoredCookie> cookies;
}

/// Attribute tags shown for a cookie.
enum CookieFlag {
  secure('Secure'),
  httpOnly('HttpOnly'),
  hostOnly('Host only'),
  session('Session');

  const CookieFlag(this.label);
  final String label;
}

/// True when [c] matches [query] (case-insensitive) on name, value or domain.
bool cookieMatches(StoredCookie c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return c.name.toLowerCase().contains(q) ||
      c.value.toLowerCase().contains(q) ||
      (c.domain ?? '').toLowerCase().contains(q);
}

/// Filters [cookies] by [query] and groups them by domain (domains sorted, cookies by name then path).
List<CookieGroup> groupCookies(Iterable<StoredCookie> cookies, String query) {
  final by = <String, List<StoredCookie>>{};
  for (final c in cookies) {
    if (!cookieMatches(c, query)) continue;
    by.putIfAbsent(c.domain ?? '', () => []).add(c);
  }
  final domains = by.keys.toList()..sort();
  return [
    for (final d in domains)
      CookieGroup(
        d,
        by[d]!..sort((a, b) {
          final n = a.name.compareTo(b.name);
          return n != 0 ? n : (a.path ?? '/').compareTo(b.path ?? '/');
        }),
      ),
  ];
}

/// Flags to show for [c], in display order.
List<CookieFlag> cookieFlags(StoredCookie c) => [
  if (c.secure) CookieFlag.secure,
  if (c.isHttpOnly) CookieFlag.httpOnly,
  if (c.hostOnly) CookieFlag.hostOnly,
  if (c.expires == null) CookieFlag.session,
];

/// Relative expiry such as `in 2 h`, `in 3 days` or `expired`; `Session` when there is no expiry.
String relativeExpiry(DateTime? expires, DateTime now) {
  if (expires == null) return 'Session';
  final d = expires.difference(now);
  if (d <= Duration.zero) return 'expired';
  if (d.inMinutes < 1) return 'in <1 min';
  if (d.inHours < 1) return 'in ${d.inMinutes} min';
  if (d.inDays < 1) return 'in ${d.inHours} h';
  if (d.inDays < 90) return 'in ${d.inDays} ${d.inDays == 1 ? 'day' : 'days'}';
  final months = d.inDays ~/ 30;
  if (months < 24) return 'in $months months';
  return 'in ${d.inDays ~/ 365} years';
}

/// Summary such as `3 cookies · 2 domains`.
String cookieCountLabel(int cookies, int domains) =>
    '$cookies ${cookies == 1 ? 'cookie' : 'cookies'} · '
    '$domains ${domains == 1 ? 'domain' : 'domains'}';

/// `name=value` form of [c].
String cookiePair(StoredCookie c) => '${c.name}=${c.value}';

/// Local date and time as `YYYY-MM-DD HH:MM:SS`.
String cookieDateText(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final l = d.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)} '
      '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}
