# open_rest

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Releasing

Releases are built by GitHub Actions (`.github/workflows/release.yml`).

1. Bump `version:` in `pubspec.yaml` (for example `2.1.0+1`) and merge it.
2. Tag the commit with the same version and push the tag:

   ```sh
   git tag v2.1.0
   git push origin v2.1.0
   ```

3. The workflow checks that the tag matches `pubspec.yaml`, runs analyze and the tests, builds every platform and
   publishes a GitHub Release with these files and `SHA256SUMS.txt`:

   | File (under the version folder) | Platform |
   | --- | --- |
   | `open_rest-<version>-macos.dmg` | macOS, Apple Silicon and Intel: open it and drag OpenRest to Applications |
   | `open_rest-<version>-macos.pkg` | macOS installer package (unsigned): installs OpenRest into Applications |
   | `open_rest-<version>-windows-setup.exe` | Windows 10/11 installer (Inno Setup) with a Start menu entry |
   | `open_rest-<version>-windows.msix` | Windows 10/11 MSIX package (unsigned: sign it with your own certificate to sideload it) |
   | `open_rest-<version>-linux.deb` | Debian / Ubuntu: `sudo apt install ./open_rest-<version>-linux.deb` |
   | `open_rest-<version>-linux.rpm` | Fedora / RHEL / openSUSE: `sudo dnf install ./open_rest-<version>-linux.rpm` |
   | `open_rest-<version>-linux.AppImage` | Any x86-64 Linux: `chmod +x` it and run it |

   Installers are built with [fastforge](https://fastforge.dev) (`fastforge package --platform <os> --targets <target>`);
   their settings live next to each platform, in `macos|windows|linux/packaging/<target>/make_config.yaml`. To build one
   locally, run `dart pub global activate fastforge` and the same command (the DMG also needs `npm install -g appdmg`).

A tag with a suffix (`v2.1.0-beta.1`) is published as a pre-release. To try the build without publishing, run the
**Release** workflow by hand from the Actions tab. The macOS app is ad-hoc signed, not notarised, so on first launch
right-click it and choose Open.

