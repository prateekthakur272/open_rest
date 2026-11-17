# OpenRest architecture

OpenRest is a Flutter desktop app. `lib/main.dart` sets up the window, builds the root widget and the macOS menu bar; everything else is in `lib/`, split into layers. For the folder-by-folder tour see [project-structure.md](project-structure.md).

## Layers

| Layer | Owns | May depend on |
|---|---|---|
| `core/` | Domain and data: requests and collections, sending requests, scripts, workflows, GraphQL, WebSocket, code generation, import / export, files on disk, logging | `utils/` |
| `utils/` | Constants and small helpers: `AppConfig`, `AppMetadata`, `Paths`, YAML / JSON / XML, `UpdateChecker`, `IssueReport` | `core/` (see exceptions) |
| `theme/`, `platform/` | The palette and icons; operating-system access | `core/logging`, `utils/` |
| `components/` | Reusable widgets with no knowledge of any feature | `theme/`, `core/` (model and text helpers) |
| `app/` | Application state: `AppState`, per-tab sessions, the dialog list | `core/`, `platform/` |
| `features/*` | One folder per screen area | `app/`, `components/`, `core/`, `theme/`, `platform/` |
| `main.dart`, `features/shell` | Composition: assembles the features into the window | everything |

The rule that matters most: **`core/` never imports `app/`, `features/`, `components/`, `theme/` or `platform/`.** Everything in it can be tested without a UI. This is checked by reading the imports; no tool enforces it, so keep it true when you add code.

### Known exceptions

These are small and listed so nobody copies them:

- `utils/` is not a pure leaf: `yml.dart` and `bru.dart` read the model, and `app_metadata.dart`, `update_checker.dart` use `core/` logging and storage. `core/` in turn uses `utils/`. They depend on each other at file level, not in a cycle.
- `components/` imports a few things from `core/`: the model, `Variables` (so `Field` can highlight `{{vars}}`) and the workflow value parser (for syntax highlighting).
- `app/` imports three files from `features/` (the node-settings controller and logic, and the runner's result filter), because sessions hold that state.

## State

- **`AppState`** (`app/app_state.dart`) is a `ChangeNotifier` and the single owner of application state: open collections, tabs, the active environment, settings, the dialog that is showing. Widgets reach it through `AppScope` (an `InheritedNotifier`): `AppScope.of(context)` subscribes to changes, `AppScope.read(context)` does not.
- **Sessions** (`app/sessions.dart`) hold the state of one tab and notify through `SessionNotifier`: `RequestTab` (draft, saved copy, response history, selected sub-tab), `RunnerSession`, `WorkflowSession`, `CollectionSession` and `WebSocketSession` (connection state and message log). `StateList` and `StateMap` notify on every mutation, so a screen listens to its session with a `ListenableBuilder` and rebuilds only itself.
- **Operations** on `AppState` are extension methods grouped by topic (`app_state_sidebar.dart`, `_environments`, `_workflows`, `_transfer`), so the class holds state and the files hold behaviour.
- **Dialogs** are cases of the sealed `Modal` class. Setting `state.modal = ModalX(...)` shows one; `Modals` (`features/shell/modals.dart`) maps every case to its widget with an exhaustive `switch`, so the compiler tells you when a dialog is missing.
- **Menus** are data (`AppMenus.build` in `features/shell/menus.dart`). On macOS `main.dart` converts them to the native menu bar; on Windows and Linux `TitleMenus` draws them inside the custom title bar.

## What happens when you press Send

`AppState.send(tab)` wraps the request in a `RequestNode` and runs `Execution` (`core/run/runner.dart`), which does everything for one request:

1. Resolve the chain of inherited settings (collection, then folders, then the request) and the variable scopes.
2. Start the JavaScript engine only if something needs it (scripts, tests, assertions, post-response variables).
3. Run the **pre-request scripts**: collection, folders, request.
4. `prepare()`: interpolate `{{variables}}`, merge inherited headers, apply auth (Basic, Bearer, API key, OAuth 2 token fetch), build the body.
5. Send with `HttpExecutor` (`core/http`): redirects, cookies, proxy, TLS and client certificates, timeout. Digest auth retries once on a 401 challenge.
6. Evaluate **post-response variables**, run the **post-response scripts** (request, folders, collection), then **assertions** and **tests**.
7. Return an `ExecResult` (request, response, test results, console output) that the response viewer, the history and the runner all use.

The collection **runner** and the **workflow** engine call `Execution` for each request step, so scripts, variables and auth behave identically everywhere.

### Other protocols

- **GraphQL** is a body mode, not a separate pipeline: the query, variables and operation name are packed into the JSON body of a normal `POST`. `core/graphql` adds operation parsing, formatting and the introspection schema model that powers the Docs menu.
- **WebSocket** requests have `kind: ws`. They do not use `Execution.run`; `AppState.connectWs` resolves the URL, headers and auth with `Execution.prepare` and hands them to `WebSocketSession`, which owns the connection and the message log. The collection runner skips them.
- **Auto-generated headers** shown in the Headers table are computed by `Execution.generatedHeaders` and `core/http/generated_headers.dart`, mirroring what the client really sends. A test compares the list against a real server.

## Data on disk

| What | Where |
|---|---|
| Collections, requests, folders, environments, workflows, docs | The collection folder the user chose ([file format](file-format.md)) |
| Settings | `~/.openrest/settings.json` |
| Open collections, tabs (and each tab's sub-tab), sidebar and layout | `~/.openrest/state.json` |
| Small flags (for example the update the user dismissed) | `~/.openrest/prefs.json` |
| Window size and position | `~/.openrest/window.json` |
| Secret variable values | `~/.openrest/secrets.json` |
| Global environments | `~/.openrest/environments/` |
| Log | `~/.openrest/openrest.log` |

All of it is read and written by `AppStore` and `Collections` in `core/storage/storage.dart`, and all paths come from `Paths` (`utils/paths.dart`). The app does not use the platform preference store (`shared_preferences`); a test fails if it comes back.

## Identity and version

- **`AppConfig`**: compile-time constants (name, vendor, links).
- **`AppMetadata`**: what the running app reports about itself, read at startup from the platform (`package_info_plus`): version, build number and bundle id. The version is written once, in `pubspec.yaml`.

## Conventions

- One responsibility per file. A file past a few hundred lines is a sign to split it by topic.
- Failures are never swallowed silently: use `Log.warning` / `Log.error`, or `Log.orElse` for work that is allowed to fail. Never log secrets or request bodies.
- Secrets never go into collection files.
- The on-disk YAML only grows: add optional fields and keep reading old files.
- Drag gestures use `kDragDevices` (mouse, touch and pen, not the trackpad), so a two-finger scroll never drags a tile or a divider.

## Tests

`test/` holds unit tests for the core and widget tests for the UI. Run `flutter test`. See [contributing](contributing.md#tests) for the helpers and patterns.
