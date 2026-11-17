import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_rest/utils/app_config.dart';
import 'package:open_rest/utils/app_metadata.dart';
import 'package:open_rest/utils/issue_report.dart';
import 'package:open_rest/utils/paths.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(AppMetadata.reset);

  test('points at the new-issue page of the project', () {
    final u = IssueReport.url();
    expect('${u.scheme}://${u.host}${u.path}', AppConfig.ISSUES_URL);
    expect(u.path, endsWith('/issues/new'));
    expect(u.queryParameters.keys, ['body']);
  });

  test('an optional title is passed along', () {
    expect(
      IssueReport.url(title: 'Crash on start').queryParameters['title'],
      'Crash on start',
    );
  });

  test(
    'the template asks for the usual details and says which app and OS',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'OpenRest',
        packageName: 'dev.prateekthakur.openrest',
        version: '2.1.0',
        buildNumber: '1',
        buildSignature: '',
      );
      await AppMetadata.load();
      final body = IssueReport.url().queryParameters['body']!;
      expect(body, contains('**What happened?**'));
      expect(body, contains('**Steps to reproduce**'));
      expect(body, contains('- OpenRest 2.1.0+1'));
      expect(body, contains('- OS: ${Platform.operatingSystem}'));
    },
  );

  test('it survives the trip through a URL, newlines included', () {
    final u = Uri.parse(IssueReport.url(title: 'a & b = c').toString());
    expect(u.queryParameters['title'], 'a & b = c');
    expect(u.queryParameters['body'], IssueReport.body());
    expect(IssueReport.body(), contains('\n'));
  });

  test('nothing private goes into the report', () {
    final all = IssueReport.url().toString() + IssueReport.body();
    final home = Paths.home;
    if (home.isNotEmpty) expect(all, isNot(contains(home)));
    expect(all.toLowerCase(), isNot(contains('openrest.yaml')));
    expect(all, isNot(contains('/Users/')));
  });

  test('the link is short enough for a browser', () {
    expect(IssueReport.url().toString().length, lessThan(2000));
  });
}
