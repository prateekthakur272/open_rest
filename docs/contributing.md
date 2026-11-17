# Contributing to OpenRest

Thanks for helping. This page covers how to set up, how the code is organised, what we expect from a change and how to send it.

## Ways to help

- **Report a bug.** The quickest way is the **bug icon** in the status bar (bottom left): it opens a new GitHub issue with a template and your OpenRest version and operating system already filled in (nothing else is added). Say what happened, what you expected and the steps to reproduce. A screenshot or a sanitised request file helps a lot.
- **Suggest a feature** by describing the problem you are trying to solve before the solution.
- **Improve the docs**: fix a typo, add an example, clarify a step. Docs live in `docs/`.
- **Send a pull request** for a fix or a feature.

## Setting up

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (stable) with the desktop toolchain for your system. CI uses Flutter 3.50.0.
2. Fork and clone the repository, then `flutter pub get`.
3. Run the app: `flutter run -d macos` (or `-d windows`, `-d linux`).
4. Run the checks: `flutter analyze` and `flutter test`.

On Linux the tests need the QuickJS library the script engine loads; see [building and releasing](building-and-releasing.md#everyday-commands).

Open the project in VS Code or Android Studio / IntelliJ with the Flutter plugin.

## Finding your way around

Read [project-structure.md](project-structure.md) first, then [ARCHITECTURE.md](ARCHITECTURE.md) for the rules. The short version:

- `features/<name>/` for a part of the app a user can point at, `components/` for reusable widgets, `utils/` for small helpers and constants, `core/` for logic with no UI, `app/` for state.
- **`core/` never imports `app/`, `features/` or `components/`.** Keep it testable without a UI.
- A new reusable widget goes in `components/`. A new helper goes in `utils/`. Prefer reusing what is there over writing a second copy.

## Conventions

**Dart**

- Format with `dart format lib test` and keep `flutter analyze` clean. The lints are `flutter_lints` (see `analysis_options.yaml`).
- Keep files focused. If a file passes a few hundred lines or mixes two responsibilities, split it by responsibility into the same folder.
- Make things private (`_name`) unless another file needs them.
- Comments explain *why*, not *what*. Public members that are not obvious get a one-line `///` comment.
- Failures are never swallowed silently: use `Log.warning` / `Log.error`. Never log secrets or request bodies.

**UI**

- Use the palette (`context.pal`) and the shared components (`T`, `Btn`, `IconBtn`, `Field`, `KVTable`, `Segmented`, `ModalBox`, `Tabs`) rather than raw Material widgets, so the look stays consistent in light and dark.
- Give widgets a `ValueKey` when a test needs to find them.
- Keep state in `AppState` or a session class (`app/sessions.dart`), not scattered in widgets, if more than one place reads it.
- Keep the UI usable by keyboard.
- Drag gestures (tiles, dividers, the window) must use `kDragDevices` so a trackpad scroll never starts a drag.

**Files and data**

- Never change the on-disk YAML format in a way that breaks existing collections. Add optional fields; keep reading old ones.
- Secrets never go in collection files.
- Do not use `shared_preferences`. Settings go in `AppSettings` (`settings.json`), session state in `SavedState` (`state.json`), and small flags through `AppStore.flag` / `AppStore.setFlag` (`prefs.json`). A test fails if the package comes back.

**Documentation**

- A user-visible change should update the matching page in `docs/` and, if it adds a feature, [features.md](features.md).
- Menu and shortcut changes should update [keyboard-shortcuts.md](keyboard-shortcuts.md).

## Tests

```bash
flutter test
```

Tests are in `test/`, one file per area (core logic, import / export, TLS, request, response, workflows, shell and so on).

- **Logic** is tested with plain unit tests. Where HTTP is needed, start a throw-away server on a random local port with `startServer` and answer with `respond` (both in `test/helpers.dart`). Real sockets are used, not mocks.
- **UI** is tested with `testWidgets`: build the app with `host(state)` (from `test/shell_widget_test.dart`) or a small harness, drive it with `tap` / `enterText` / gestures, and assert on what is on screen or on `AppState`.
- Tests that read or write settings call `useTempHome()` first, so they never touch your real `~/.openrest`.
- **Do not mix real sockets and `testWidgets` in the same file.** Flutter's widget-test setup replaces the HTTP client with a mock that answers `400`, so a server test in that file fails. Keep server tests in their own file (as `ws_test.dart` and `ws_view_test.dart` do).
- A test that replaces `FlutterError.onError` must restore it, or a failure turns into a hang.
- Add a test with every bug fix, using the failing case.

If your change affects a screenshot in the docs, retake it (see [building-and-releasing.md](building-and-releasing.md#the-screenshots-in-these-docs)).

## Pull requests

1. Create a branch from `main`: `git checkout -b fix/short-description`.
2. Keep the change focused. Separate refactors from behaviour changes.
3. Make sure `flutter analyze` and `flutter test` pass.
4. Write a clear description: what changed, why, how you tested it, and a before/after screenshot for UI changes.
5. Be ready to iterate on review comments.

### Commit messages

A short imperative summary, then a blank line and the reason if it is not obvious:

```
Fix path parameters lost when the URL is edited

The query string was re-parsed and dropped :name segments.
```

## Reporting security problems

Please do not open a public issue for a security problem. Contact the maintainers privately and give them time to fix it before disclosure.

## Code of conduct

Be kind and assume good intent. Critique code, not people. Harassment of any kind is not tolerated.
