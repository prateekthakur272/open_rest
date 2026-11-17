# Building and releasing

## Requirements

- **Flutter** (stable channel). CI uses 3.50.0; the app needs a Dart SDK matching `sdk: ^3.14.0` in `pubspec.yaml`.
- The Flutter desktop toolchain for the system you build on: Xcode on macOS, Visual Studio with the "Desktop development with C++" workload on Windows, and on Linux:

  ```bash
  sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
  ```

- To build an installer you must be on the target operating system: a DMG needs macOS, an installer `.exe` needs Windows, a `.deb` needs Linux.

## Everyday commands

```bash
flutter pub get                 # install dependencies
flutter run -d macos            # run the app (or -d windows, -d linux)
flutter analyze                 # static analysis (flutter_lints)
flutter test                    # run all tests
dart format lib test            # format the code
```

On **Linux**, `flutter test` needs the QuickJS library that the script engine loads. Point it at the copy shipped inside the package:

```bash
export LIBQUICKJSC_TEST_PATH=$(find ~/.pub-cache -path '*flutter_js-*/linux/shared/libquickjs_c_bridge_plugin.so' | head -n 1)
flutter test
```

macOS and Windows tests need nothing extra.

## Where the app's identity comes from

| What | Where |
|---|---|
| **Version** and build number | `version:` in `pubspec.yaml` (for example `2.2.0+1`). It is written only there; the build passes it to the app and `AppMetadata` reads it back at runtime |
| Name, vendor, links | `AppConfig` in `lib/utils/app_config.dart` |
| macOS bundle id | `PRODUCT_BUNDLE_IDENTIFIER` in `macos/Runner/Configs/AppInfo.xcconfig` |
| Linux application id | `APPLICATION_ID` in `linux/CMakeLists.txt` |
| Executable name | `BINARY_NAME` in `windows/CMakeLists.txt` and `linux/CMakeLists.txt` |

`AppMetadata.fallbackBundleId` repeats the bundle id for platforms that do not report one. If you ever change the id, change it there too, and do not change it after a release: settings and installs follow it.

## Installers

Installers are made with [Fastforge](https://fastforge.dev). Each format has a `make_config.yaml` next to its platform folder:

| Platform | Command | Needs |
|---|---|---|
| macOS | `fastforge package --platform macos --targets dmg,pkg` | `npm install -g appdmg` |
| Windows | `fastforge package --platform windows --targets exe,msix` | [Inno Setup](https://jrsoftware.org/isinfo.php) |
| Linux | `fastforge package --platform linux --targets deb,rpm,appimage` | `rpm`, `patchelf`, `locate` and [`appimagetool`](https://github.com/AppImage/appimagetool) |

```bash
dart pub global activate fastforge
```

Fastforge builds the release app itself, then packages it. The files are written to `dist/<version>/` (the folder is git-ignored). Two things to know:

- By default Fastforge runs `flutter clean` first. That removes `.dart_tool/`, so run `flutter pub get` afterwards, or pass `--skip-clean` to keep your build.
- The macOS app is a universal binary (Apple silicon and Intel), so one DMG and one PKG cover both.

| Format | Config | What it is |
|---|---|---|
| `dmg` | `macos/packaging/dmg/make_config.yaml` | Drag-to-Applications disk image |
| `pkg` | `macos/packaging/pkg/make_config.yaml` | macOS installer package |
| `exe` | `windows/packaging/exe/make_config.yaml` | Windows setup program (Inno Setup) |
| `msix` | `windows/packaging/msix/make_config.yaml` | MSIX package (unsigned) |
| `deb` | `linux/packaging/deb/make_config.yaml` | Debian / Ubuntu package |
| `rpm` | `linux/packaging/rpm/make_config.yaml` | Fedora / RHEL / openSUSE package |
| `appimage` | `linux/packaging/appimage/make_config.yaml` | Single-file app for any x86-64 distribution |

None of the installers are code-signed or notarised yet. On macOS, right-click the app and choose **Open** the first time; Windows may show a SmartScreen warning; an unsigned MSIX will not install until it is signed with a certificate you trust.

## Releasing a new version

Releases are built by GitHub Actions (`.github/workflows/release.yml`) when you push a version tag.

1. Set the new version in `pubspec.yaml` (for example `version: 2.3.0+1`), commit and merge it.
2. Tag the commit with the same version and push the tag:

   ```bash
   git tag v2.3.0
   git push origin v2.3.0
   ```

3. The workflow then:
   1. **verifies** that the tag matches the `pubspec.yaml` version (a suffix like `v2.3.0-beta.1` is allowed and marks a pre-release), then runs `flutter analyze` and `flutter test`;
   2. builds the **macOS**, **Windows** and **Linux** installers in parallel with Fastforge;
   3. writes `SHA256SUMS.txt` and publishes a **GitHub Release** with every installer and generated release notes. It only publishes if all three builds succeed.

You can also run the **Release** workflow by hand from the Actions tab: it builds everything and keeps the installers as downloadable artifacts, without publishing.

The installer files carry Fastforge's default names (`open_rest-<version>-<platform>…`). The in-app update check reads the latest release's tag, so a release has to be a published GitHub release, not only a tag.

CI (`.github/workflows/ci.yml`) runs `flutter analyze` and `flutter test` on every push to `main` and every pull request.

## Changing the app icon

- **macOS:** replace the images in `macos/Runner/Assets.xcassets/AppIcon.appiconset/`.
- **Windows:** `windows/runner/resources/app_icon.ico` (include 16 to 256 px sizes).
- **Linux:** `linux/runner/resources/icon.png`.

The installers reuse these files.

## The screenshots in these docs

The images in `docs/screenshots/` are 1360×860 captures of the app showing a demo "Pet Store API" collection, so they never show real data. They are plain files; nothing in the build regenerates them. If you change the UI noticeably, retake the affected ones the same way (a window that size, the demo collection) and replace the file with the same name so the links keep working.
