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

   | File | Platform |
   | --- | --- |
   | `OpenRest-<version>-macos-universal.dmg` | macOS, Apple Silicon and Intel |
   | `OpenRest-<version>-windows-x64.zip` | Windows 10/11 (unzip and run `OpenRest.exe`) |
   | `OpenRest-<version>-linux-x64.tar.gz` | Linux (extract and run `OpenRest`) |

A tag with a suffix (`v2.1.0-beta.1`) is published as a pre-release. To try the build without publishing, run the
**Release** workflow by hand from the Actions tab. The macOS app is ad-hoc signed, not notarised, so on first launch
right-click it and choose Open.

