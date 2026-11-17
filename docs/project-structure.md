# Project structure

OpenRest is a Flutter desktop app (macOS, Windows and Linux) written in Dart. There is one package, `open_rest`, and no Android, iOS or web target.

```
open_rest/
├── README.md
├── pubspec.yaml                 dependencies, version, assets
├── analysis_options.yaml        lints (flutter_lints)
├── assets/prelude.js            the JavaScript helpers loaded into every script run
├── lib/                         all Dart source (see below)
├── test/                        unit and widget tests
├── docs/                        user and contributor documentation
│   └── screenshots/             images used by the docs
├── macos/  windows/  linux/     the Flutter runners, plus packaging/ with the installer settings
├── .github/workflows/           CI (ci.yml) and releases (release.yml)
└── .marketplace/                the app-marketplace listing and its screenshots
```

Each platform folder has a `packaging/` directory with one `make_config.yaml` per installer format (see [building and releasing](building-and-releasing.md)):

| Folder | Formats |
|---|---|
| `macos/packaging/` | `dmg`, `pkg` |
| `windows/packaging/` | `exe` (Inno Setup), `msix` |
| `linux/packaging/` | `deb`, `rpm`, `appimage` |

## `lib/`

Every import is a `package:open_rest/...` import. The folder is the layer.

```
lib/
├── main.dart            entry point: window setup, the root widget, the macOS menu bar
├── app/                 application state
├── core/                logic with no UI
├── features/            one folder per part of the app a user can point at
├── components/          reusable widgets
├── theme/               palette, themes, icons
├── platform/            operating-system access
└── utils/               small helpers and app-wide constants
```

### `app/`: state

| File | What it holds |
|---|---|
| `app_state.dart` | `AppState`, the single owner of state (a `ChangeNotifier`), and `AppScope`, the `InheritedNotifier` that hands it to widgets |
| `app_state_sidebar.dart`, `app_state_environments.dart`, `app_state_workflows.dart`, `app_state_transfer.dart` | Operations on `AppState`, grouped by topic as extensions, so the class holds state and the files hold behaviour |
| `sessions.dart` | Per-tab state: `RequestTab`, `RunnerSession`, `WorkflowSession`, `CollectionSession`, `WebSocketSession`, plus the `StateList` / `StateMap` collections that notify on every change |
| `modal.dart` | `Modal`, a sealed class with one case per dialog |

### `core/`: logic

| Folder | What it is |
|---|---|
| `model/` | Requests, collections, folders, environments, auth, TLS, settings, `PreparedRequest`, `HttpResult` |
| `http/` | `HttpExecutor` (the HTTP client), `Variables` (`{{...}}` interpolation), the cookie jar, and `generated_headers.dart` (the headers the app adds itself) |
| `run/` | `Execution` (runs one request: scripts, variables, auth, send, assertions, tests), `Runner` (the collection runner) and the workflow engine, model and storage |
| `script/` | `ScriptEngine`, the bridge to the JavaScript engine |
| `graphql/` | Operation parsing, query formatting and the introspection schema model |
| `ws/` | The WebSocket client |
| `codegen/` | Request to code snippets |
| `interop/` | Importers and exporters |
| `storage/` | Files on disk: collections, settings, state, secrets, preferences |
| `logging/` | `Log`: levels, tags and the log file |

### `features/`: screens

One folder per part of the app:

| Folder | What it is |
|---|---|
| `shell/` | The window: layout, title bar and its gestures, tab strip, status bar, menus (as data), the command palette and which dialog is showing |
| `sidebar/` | The collection tree, drag and drop, context menus and history |
| `request/` | The request editor: params, body, headers, auth, scripts, assertions, tests, TLS, and the GraphQL pane |
| `response/` | The response viewer |
| `websocket/` | The WebSocket request view and its message log |
| `collection/` | The collection tab: overview, documentation and settings pages |
| `runner/` | The collection runner tab |
| `workflow/` | The workflow builder, its run log and steps |
| `dialogs/` | Create, open, import, export, environments, variables, cookies and node-settings dialogs |
| `preferences/` | The Preferences window |
| `onboarding/` | The first-run walkthrough |
| `developer/` | The Developer dialog |

### `components/`, `theme/`, `platform/`, `utils/`

- **`components/`**: widgets that know nothing about any one feature: text and buttons, `Field` (the variable-aware input with highlighting and autocomplete), tables (`KVTable`), code editor and viewer, JSON tree, Markdown view, diff view, overlays and menus, split panes and tabs. If a second feature needs a widget, it belongs here.
- **`theme/`**: `OpenRestTheme` (the palette and light / dark themes) and the icon set (`Ic`, `Ico`).
- **`platform/`**: the `Platform` class: clipboard, file dialogs, opening URLs, "show in Finder / Explorer".
- **`utils/`**: `AppConfig` (name, credits and links, as constants), `AppMetadata` (version, build and bundle id read from the running app), `Paths` (where files live), the YAML, JSON, XML, Bruno and diff helpers, `UpdateChecker` and `IssueReport`.

## How the pieces fit

```
main.dart ──► features/shell ──► features/* ──► app ──► core ──► utils
                                      │                    ▲
                                      └──► components ──► theme
```

- `core/` imports nothing from `app/`, `features/`, `components/`, `theme/` or `platform/`. It can be tested without a UI.
- Features read and change state through `AppState`. They do not call each other, except where one is built from another (`request` reuses `response`, `websocket` reuses the request pane, `collection` uses `dialogs`); `shell` assembles everything.
- Menus are data (`AppMenus.build`). macOS turns that data into the native menu bar (`main.dart`); Windows and Linux draw it in the title bar (`TitleMenus`). One definition serves both.
- Dialogs are cases of the `Modal` class; `Modals` picks the widget to draw with an exhaustive `switch`.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the rules behind this and the known exceptions.

## Where does new code go?

| I want to… | Put it in |
|---|---|
| Add a reusable button, input or table | `components/` |
| Add a feature | `features/<name>/`, then hook it into `features/shell` |
| Add a dialog | a case in `app/modal.dart`, the dialog in its feature, a line in `features/shell/modals.dart` |
| Add a menu item | `AppMenus.build` in `features/shell/menus.dart` |
| Add a command-palette action | `features/shell/palette.dart` |
| Add a pure helper | `utils/` |
| Change how requests are run, imported or exported | `core/` |
| Touch the operating system | `platform/` |
| Remember a small flag | `AppStore.flag` / `AppStore.setFlag` in `core/storage/storage.dart` |

## Tests

Tests live in `test/`, one file per area. See [contributing](contributing.md#tests).
