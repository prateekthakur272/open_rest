import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Chip, ThemeMode;
import 'package:open_rest/app/app_state.dart';
import 'package:open_rest/core/http/http.dart';
import 'package:open_rest/features/dialogs/cookies_dialog.dart';
import 'package:open_rest/features/dialogs/cookies_logic.dart';

import 'helpers.dart';
import 'shell_widget_test.dart' show captureErrors, errors, host;

StoredCookie _c(
  String name,
  String value,
  String domain, {
  String path = '/',
  bool secure = false,
  bool httpOnly = false,
  bool hostOnly = false,
  DateTime? expires,
}) => StoredCookie(
  name,
  value,
  domain,
  path,
  secure,
  httpOnly,
  hostOnly,
  expires,
);

void main() {
  final now = DateTime(2026, 1, 1, 12);

  group('relativeExpiry', () {
    test('session, expired and units', () {
      expect(relativeExpiry(null, now), 'Session');
      expect(
        relativeExpiry(now.subtract(const Duration(seconds: 1)), now),
        'expired',
      );
      expect(relativeExpiry(now, now), 'expired');
      expect(
        relativeExpiry(now.add(const Duration(seconds: 30)), now),
        'in <1 min',
      );
      expect(
        relativeExpiry(now.add(const Duration(minutes: 5)), now),
        'in 5 min',
      );
      expect(
        relativeExpiry(now.add(const Duration(hours: 2, minutes: 10)), now),
        'in 2 h',
      );
      expect(relativeExpiry(now.add(const Duration(days: 1)), now), 'in 1 day');
      expect(
        relativeExpiry(now.add(const Duration(days: 3)), now),
        'in 3 days',
      );
      expect(
        relativeExpiry(now.add(const Duration(days: 120)), now),
        'in 4 months',
      );
      expect(
        relativeExpiry(now.add(const Duration(days: 800)), now),
        'in 2 years',
      );
    });
  });

  group('grouping and filtering', () {
    final cookies = [
      _c('sid', 'abc', 'b.com'),
      _c('theme', 'dark', 'a.com', path: '/x'),
      _c('lang', 'en', 'a.com'),
      _c('lang', 'fr', 'a.com', path: '/a'),
    ];

    test('groups by sorted domain, cookies by name then path', () {
      final g = groupCookies(cookies, '');
      expect(g.map((x) => x.domain), ['a.com', 'b.com']);
      expect(g.first.cookies.map((x) => '${x.name}${x.path}'), [
        'lang/',
        'lang/a',
        'theme/x',
      ]);
    });

    test('filters by name, value and domain, case-insensitively', () {
      expect(groupCookies(cookies, 'SID').single.domain, 'b.com');
      expect(groupCookies(cookies, 'dark').single.cookies.single.name, 'theme');
      expect(groupCookies(cookies, 'b.co').single.domain, 'b.com');
      expect(groupCookies(cookies, 'a.com').single.cookies, hasLength(3));
      expect(groupCookies(cookies, 'zzz'), isEmpty);
    });
  });

  test('cookieFlags and labels', () {
    expect(
      cookieFlags(
        _c('a', 'b', 'x', secure: true, httpOnly: true, hostOnly: true),
      ),
      [
        CookieFlag.secure,
        CookieFlag.httpOnly,
        CookieFlag.hostOnly,
        CookieFlag.session,
      ],
    );
    expect(cookieFlags(_c('a', 'b', 'x', expires: now)), isEmpty);
    expect(cookieCountLabel(1, 1), '1 cookie · 1 domain');
    expect(cookieCountLabel(3, 2), '3 cookies · 2 domains');
    expect(cookiePair(_c('a', 'b', 'x')), 'a=b');
  });

  test('jar removeCookie and removeDomain', () {
    final jar = CookieJar();
    final a = _c('a', '1', 'x.com'),
        b = _c('b', '2', 'x.com'),
        c = _c('c', '3', 'y.com');
    jar.cookies.addAll([a, b, c]);
    jar.removeCookie(a);
    expect(jar.cookies, [b, c]);
    jar.removeDomain('x.com');
    expect(jar.cookies, [c]);
  });

  testWidgets('cookies dialog lists, filters, expands and deletes', (t) async {
    useTempHome();
    final oldOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = oldOnError);
    captureErrors();
    t.view.physicalSize = const Size(1360, 860);
    t.view.devicePixelRatio = 1;
    final jar = HttpExecutor.cookies;
    jar.removeAll();
    addTearDown(jar.removeAll);
    jar.cookies.addAll([
      _c('sid', 'abcdef', 'a.example.com', secure: true, httpOnly: true),
      _c(
        'theme',
        'dark',
        'a.example.com',
        hostOnly: true,
        expires: DateTime.now().add(const Duration(hours: 5, minutes: 30)),
      ),
      _c(
        'lang',
        'en',
        'b.example.com',
        expires: DateTime.now().add(const Duration(days: 3, hours: 1)),
      ),
    ]);
    final s = AppState();
    await t.pumpWidget(host(s));
    await t.pump();
    s.modal = ModalCookies();
    await t.pump();
    expect(find.byType(CookiesDialog), findsOneWidget);
    expect(find.text('3 cookies · 2 domains'), findsOneWidget);
    expect(find.text('a.example.com'), findsOneWidget);
    expect(find.text('Secure'), findsOneWidget);
    expect(find.text('HttpOnly'), findsOneWidget);
    expect(find.text('Host only'), findsOneWidget);
    expect(find.text('in 5 h'), findsOneWidget);
    expect(find.text('in 3 days'), findsOneWidget);

    // Collapse a group.
    await t.tap(find.byKey(const ValueKey('group-a.example.com')));
    await t.pump();
    expect(find.text('sid'), findsNothing);
    await t.tap(find.byKey(const ValueKey('group-a.example.com')));
    await t.pump();
    expect(find.text('sid'), findsOneWidget);

    // Expand a row.
    await t.tap(find.text('abcdef'));
    await t.pump();
    expect(find.byKey(const ValueKey('detail-sid')), findsOneWidget);

    // Filter.
    await t.enterText(find.byType(TextField).first, 'lang');
    await t.pump();
    expect(find.text('1 cookie · 1 domain'), findsOneWidget);
    expect(find.text('sid'), findsNothing);
    await t.enterText(find.byType(TextField).first, 'nothing-here');
    await t.pump();
    expect(find.text('No cookies match "nothing-here"'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '');
    await t.pump();

    // Delete one cookie on hover.
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.text('lang')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('delete-lang')));
    await t.pump();
    expect(jar.cookies.map((c) => c.name), ['sid', 'theme']);

    // Delete a domain.
    await mouse.moveTo(t.getCenter(find.text('a.example.com')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('delete-domain-a.example.com')));
    await t.pump();
    expect(jar.cookies, isEmpty);
    expect(find.text('No cookies yet'), findsOneWidget);
    expect(errors(t), isEmpty);
    s.modal = null;
  });

  testWidgets('clear all confirms above five cookies', (t) async {
    useTempHome();
    final oldOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = oldOnError);
    captureErrors();
    t.view.physicalSize = const Size(1360, 860);
    t.view.devicePixelRatio = 1;
    final jar = HttpExecutor.cookies;
    jar.removeAll();
    addTearDown(jar.removeAll);
    for (var i = 0; i < 6; i++) {
      jar.cookies.add(_c('c$i', 'v', 'x.com'));
    }
    final s = AppState();
    await t.pumpWidget(host(s));
    await t.pump();
    s.modal = ModalCookies();
    await t.pump();
    await t.tap(find.text('Clear all'));
    await t.pump();
    expect(jar.cookies, hasLength(6));
    expect(find.text('Clear 6 cookies'), findsOneWidget);
    await t.tap(find.text('Clear 6 cookies'));
    await t.pump();
    expect(jar.cookies, isEmpty);
    expect(errors(t), isEmpty);
    s.modal = null;
  });
}
