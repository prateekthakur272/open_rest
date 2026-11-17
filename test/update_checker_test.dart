import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/core/storage/storage.dart';
import 'package:open_rest/utils/update_checker.dart';

import 'helpers.dart';

/// A stand-in for GitHub: `/o/r/releases/latest` redirects to the latest tag's page, `/api/latest` is the REST API.
class _Github {
  _Github(this.base);
  final String base;
  int webHits = 0;
  int apiHits = 0;
  String get latest => '$base/o/r/releases/latest';
  String get api => '$base/api/latest';
}

void main() {
  setUp(useTempHome);

  /// [tag] is what the release page redirects to (null: the project has no release, so it redirects to the list).
  /// [web] / [apiStatus] replace the answer with an error status.
  Future<_Github> github({
    String? tag,
    int? web,
    int? apiStatus,
    String? apiTag,
  }) async {
    late final _Github gh;
    final srv = await startServer((r) async {
      if (r.uri.path == '/o/r/releases/latest') {
        gh.webHits++;
        if (web != null) {
          r.response.statusCode = web;
        } else {
          r.response.statusCode = 302;
          r.response.headers.set(
            'location',
            tag == null
                ? '${gh.base}/o/r/releases'
                : '${gh.base}/o/r/releases/tag/$tag',
          );
        }
        await r.response.close();
      } else {
        gh.apiHits++;
        await respond(
          r,
          apiStatus == null || apiStatus == 200
              ? jsonEncode({'tag_name': apiTag ?? tag ?? 'v0.0.1'})
              : '{"message":"rate limit"}',
          status: apiStatus ?? 200,
        );
      }
    });
    addTearDown(() => srv.close(force: true));
    return gh = _Github('http://127.0.0.1:${srv.port}');
  }

  Future<UpdateResult> check(_Github gh, [String current = '2.1.0']) =>
      UpdateChecker.check(current, latestUrl: gh.latest, apiUrl: gh.api);

  group('finding the latest release', () {
    test(
      'a newer release is reported, from the release page redirect alone',
      () async {
        final gh = await github(tag: 'v2.2.0');
        final r = await check(gh);
        expect(r.hasUpdate, isTrue);
        expect(r.version, '2.2.0');
        expect(r.failed, isFalse);
        expect(r.isDismissed, isFalse);
        expect(r.shouldShowDialog, isTrue);
        expect(gh.webHits, 1);
        expect(
          gh.apiHits,
          0,
          reason: 'the rate-limited REST API is not needed',
        );
      },
    );

    test(
      'the same or an older release is not an update, and not an error',
      () async {
        for (final tag in ['v2.1.0', 'v2.0.9', 'v1.9.9', '2.1.0']) {
          final r = await check(await github(tag: tag));
          expect(r.hasUpdate, isFalse, reason: tag);
          expect(r.failed, isFalse, reason: tag);
        }
      },
    );

    test('versions compare by number, not by text', () async {
      expect(
        (await check(await github(tag: 'v2.10.0'), '2.9.0')).hasUpdate,
        isTrue,
      );
      expect(
        (await check(await github(tag: 'v2.9.0'), '2.10.0')).hasUpdate,
        isFalse,
      );
    });

    test(
      'a project with no release yet is "no update", not a failure',
      () async {
        final gh = await github(tag: null);
        final r = await check(gh);
        expect(r.hasUpdate, isFalse);
        expect(r.failed, isFalse);
        expect(gh.apiHits, 0);
      },
    );

    test('if the release page does not answer, the REST API is used', () async {
      final gh = await github(web: 404, apiTag: 'v2.2.0');
      final r = await check(gh);
      expect(r.version, '2.2.0');
      expect(r.failed, isFalse);
      expect(gh.apiHits, 1);
    });

    test('being rate limited on the API does not matter while the release page works', () async {
      final gh = await github(tag: 'v2.2.0', apiStatus: 403);
      expect((await check(gh)).version, '2.2.0');
    });

    test(
      'rate limited everywhere is reported as a failure, never as "up to date"',
      () async {
        final gh = await github(web: 403, apiStatus: 403);
        final r = await check(gh);
        expect(r.hasUpdate, isFalse);
        expect(r.failed, isTrue);
        expect(r.error, contains('limiting requests'));
        expect(r.shouldShowDialog, isFalse);
      },
    );

    test('no connection at all is reported as a failure', () async {
      final r = await UpdateChecker.check(
        '2.1.0',
        latestUrl: 'http://127.0.0.1:1/o/r/releases/latest',
        apiUrl: 'http://127.0.0.1:1/api/latest',
      );
      expect(r.failed, isTrue);
      expect(r.error, 'no connection to GitHub');
    });

    test('an API answer that is not a release is a failure', () async {
      final srv = await startServer((r) async {
        if (r.uri.path.contains('releases')) {
          r.response.statusCode = 500;
          await r.response.close();
        } else {
          await respond(r, '{"name":"no tag"}');
        }
      });
      addTearDown(() => srv.close(force: true));
      final base = 'http://127.0.0.1:${srv.port}';
      final r = await UpdateChecker.check(
        '2.1.0',
        latestUrl: '$base/o/r/releases/latest',
        apiUrl: '$base/api/latest',
      );
      expect(r.failed, isTrue);
      expect(r.hasUpdate, isFalse);
    });
  });

  group('"Later"', () {
    test('is remembered in prefs.json for that version only', () async {
      final gh = await github(tag: 'v2.2.0');
      await UpdateChecker.dismissVersion('2.2.0');

      final file = File('${AppStore.dir}/prefs.json');
      expect(jsonDecode(file.readAsStringSync()), {
        'dismissedUpdateVersion': '2.2.0',
      });
      expect(UpdateChecker.isDismissed('2.2.0'), isTrue);

      final r = await check(gh);
      expect(
        r.hasUpdate,
        isTrue,
        reason: 'still an update: the status-bar icon stays',
      );
      expect(r.isDismissed, isTrue);
      expect(r.shouldShowDialog, isFalse);

      final newer = await check(await github(tag: 'v2.3.0'));
      expect(newer.isDismissed, isFalse);
      expect(newer.shouldShowDialog, isTrue);
    });

    test('a manual check clears the dismissal', () async {
      await UpdateChecker.dismissVersion('2.2.0');
      await UpdateChecker.clearDismissed();
      expect(UpdateChecker.isDismissed('2.2.0'), isFalse);
      expect(
        (await check(await github(tag: 'v2.2.0'))).shouldShowDialog,
        isTrue,
      );
    });
  });
}
