# Troubleshooting

## Where OpenRest keeps its files

`~/.openrest` (Windows: `%USERPROFILE%\.openrest`). **Help ▸ Show Data Folder** opens it.

| File | Holds |
|---|---|
| `settings.json` | Preferences |
| `state.json` | Open collections, tabs, layout, active environments |
| `prefs.json` | Small flags, such as the update you dismissed |
| `window.json` | Window size and position |
| `secrets.json` | Values of secret variables |
| `environments/` | Global environments |
| `openrest.log` | Log of warnings and errors |

Collections are never inside it. To start fresh, quit OpenRest and move the folder, or use **Preferences ▸ Data ▸ Reset preferences** for settings only.

## Requests

- **"Invalid URL" or no response.** Check the scheme and host. A bare host gets `http://`. Hover the resolved-URL line to see what is really sent.
- **`undefined: name` chip under the URL.** A `{{variable}}` has no value. Select an environment (status bar) or define it. See [environments](environments-and-variables.md).
- **Certificate errors on a local server.** Turn off **Preferences ▸ Network ▸ Verify SSL certificates**, or add a CA bundle on the TLS page.
- **Needs a client certificate.** Set it on the request, folder or collection TLS page. Relative paths resolve from the collection folder.
- **Too many redirects / redirect not followed.** See **Preferences ▸ Requests**.
- **Timeout.** Raise it in Preferences ▸ Requests or the request's Settings tab (0 = no limit).
- **Proxy.** Make sure **Preferences ▸ Proxy** is off if you do not use one.
- **Request is missing a header you did not set.** See the auto-generated rows at the bottom of the Headers table (eye button to show them).
- **GraphQL schema will not load.** The server may have introspection turned off; the Docs panel says what it received.
- **WebSocket will not connect.** Use `ws://` or `wss://`; check headers, auth and subprotocols. The log shows the reason. The collection runner skips WebSocket requests.

## Scripts and tests

- **A script error** shows as a failing row in the Tests tab; `console.log` output is in the Console tab.
- **`fetch`, `process`, `Buffer`, `require` of other modules** are not available in scripts. See [scripting](scripting-and-testing.md).
- Scripts using `bru.sleep` are limited to 60 seconds per call.

## Files and collections

- **Edited files elsewhere?** OpenRest reloads when you return to the window; the reload button forces it.
- **A request does not show.** Hidden files and the `node_modules`, `.git`, `environments` and `workflows` folders are not scanned for requests.
- **Open collection fails.** Choose the folder that contains `openrest.yaml`.
- **Secret values missing on another machine.** They are stored in `~/.openrest/secrets.json`, not in the collection.

## Updates and reports

- **Check for Updates** failing means GitHub could not be reached; try again later.
- Click the **bug icon** in the status bar to report a problem. Only the OpenRest version and your operating system are filled in.
