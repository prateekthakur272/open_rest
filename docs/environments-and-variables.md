# Environments and variables

Write `{{name}}` anywhere: URL, headers, body, auth, scripts, WebSocket messages. Defined variables are highlighted green, missing ones red, and typing `{{` autocompletes.

![Environments](screenshots/environments.png)

## Environments

- **Collection environments** live in `<collection>/environments/*.yaml` and belong to that collection.
- **Global environments** live in `~/.openrest/environments/` and are shared by every collection, with the lowest precedence.
- Choose the active ones from **Request ▸ Environment** / **Global Environment**, the status bar, or the command palette.
- Manage them in the Environments dialog: new, duplicate, delete, activate, revert, save, bulk edit (`KEY=value` per line) and filter.
- The active environments are remembered between launches.

### Secrets

Tick **secret** on a variable and its value is not written to the YAML file; it is stored in `~/.openrest/secrets.json` and masked in the editor. Use secrets for tokens and passwords you commit collections with.

## Precedence

When a name is defined in several places, the first match wins:

1. Workflow step references (`s1.…`)
2. `process.env.NAME`
3. Runtime variables (set by scripts, post-response variables, workflow outputs)
4. Request variables
5. Folder variables (the innermost folder wins)
6. Active collection environment
7. Collection variables
8. Active global environment

**View ▸ Variables…** shows what is in scope and lets you clear runtime variables.

## Variables on requests, folders and collections

The **Vars** tab has **Pre Request** (name and value, set before sending) and **Post Response** (name and an expression such as `res.body.id`, stored as a runtime variable after the response). Folders and collections have the same tables on their Variables page.

## Dynamic variables

| Variable | Value |
|---|---|
| `{{$guid}}`, `{{$randomUUID}}` | A random UUID |
| `{{$timestamp}}` | Unix time in seconds |
| `{{$isoTimestamp}}` | UTC time, ISO 8601 |
| `{{$randomInt}}` | 0 to 999 |
| `{{$randomBoolean}}` | `true` or `false` |
| `{{$randomEmail}}` | For example `user123@example.com` |
| `{{$randomFirstName}}`, `{{$randomLastName}}` | A random name from a short list |

## `.env` files and `process.env`

`{{process.env.NAME}}` reads `NAME` from a `.env` file in the collection folder (`KEY=value` lines, `#` comments), then from the system environment. Scripts use `bru.getProcessEnv('NAME')`. Keep `.env` out of git.

## Structured values

Dotted access reads into JSON values: `{{user.id}}`, `{{order.items[0].sku}}`. Values may themselves contain `{{variables}}`. Unknown names are left as written.
