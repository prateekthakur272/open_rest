// ignore_for_file: constant_identifier_names

/// Static application configuration: the name, credits and links shown in the About and developer dialogs.
///
/// Compile-time constants only. What the running app reports about itself (version, build number, bundle id) is
/// read at runtime by `AppMetadata` in utils/app_metadata.dart.
final class AppConfig {
  const AppConfig._();

  static const String NAME = 'OpenRest';

  static const String VENDOR = 'Prateek Thakur';
  static const String DESCRIPTION =
      'An open, file-based API client: requests, environments and workflows that live in plain folders.';
  static const String HOMEPAGE =
      'https://github.com/prateekthakur272/open_rest';
  static const String DEVELOPER_URL = 'https://github.com/prateekthakur272';
  static const String MORE_APPS_URL =
      'https://prateekthakur272.github.io/github-marketplace/';
  static const String TAGLINE =
      'An open, file-based API client — requests, environments and workflows that live in plain folders.';
}
