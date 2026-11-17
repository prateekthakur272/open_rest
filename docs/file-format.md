# File format

A collection is a folder. Everything is YAML, so it diffs cleanly and lives in git.

```
my-api/
  openrest.yaml          # collection settings
  .env                   # optional, read by {{process.env.X}}
  environments/dev.yaml
  workflows/Checkout.yaml
  Ping.yaml              # a request
  Users/
    folder.yaml          # folder settings
    Get user.yaml
```

Requests are any `*.yaml` / `*.yml` file. Hidden entries and the folders `node_modules`, `.git`, `environments` and `workflows` are not scanned for requests. Requests sort before folders, then by `seq`, then name. Empty values are left out, and OpenRest keeps reading older files, so new fields are always optional.

## Request

```yaml
name: Create user
seq: 2
method: POST
url: '{{baseUrl}}/users/:orgId'
params:
  query:
    - {name: notify, value: 'true'}
  path:
    - {name: orgId, value: '{{orgId}}'}
headers:
  - {name: X-Request-Id, value: '{{$guid}}'}
body:
  type: json
  json: |-
    {"name": "Ada", "email": "{{$randomEmail}}"}
auth:
  type: bearer
  token: '{{token}}'
vars:
  post:
    - {name: userId, value: res.body.id}
assertions:
  - {name: res.status, value: eq 201}
scripts:
  pre: |-
    req.setHeader('X-Time', Date.now());
tests: |-
  test('has id', () => expect(res.body).to.have.property('id'));
docs: Creates a user in the organization.
settings:
  timeout: 5000
```

Keys: `name`, `seq`, `kind` (`ws` only), `method`, `url`, `params.query` / `params.path`, `headers`, `body`, `ws`, `auth`, `vars.pre` / `vars.post`, `assertions`, `scripts.pre` / `scripts.post`, `tests`, `docs`, `settings` (`encodeUrl`, `timeout`, `tls`).

List entries are `{name, value}` and may add `enabled: false`, `file: true` (multipart file) or `contentType`.

**Body `type`**: `none`, `json`, `text`, `xml`, `graphql`, `formUrlEncoded`, `multipartForm`, `file`, with the matching key (`json`, `text`, `xml`, `graphql` plus `graphqlVariables` and `graphqlOperation`, `form`, `multipart`, `file`).

**Auth**: `{type: none|inherit}`, `{type: basic|digest, username, password}`, `{type: bearer, token}`, `{type: apikey, key, value, placement: header|queryparams}`, `{type: oauth2, grantType, tokenUrl, clientId, clientSecret, scope, username, password}`. A request omits `auth` when it inherits.

**TLS** (`settings.tls`, or `tls` on a folder or collection): `mode` (`none` or `custom`), `format` (`pfx` or `pem`), `pfx`, `cert`, `key`, `ca`, `passphrase`. Only paths are stored.

## GraphQL

```yaml
name: List repositories
method: POST
url: https://api.example.com/graphql
body:
  type: graphql
  graphql: |-
    query Repos($first: Int!) { viewer { repositories(first: $first) { nodes { name } } } }
  graphqlVariables: |-
    { "first": 10 }
  graphqlOperation: Repos
```

Sent as JSON `{query, operationName, variables}`.

## WebSocket

```yaml
name: Echo server
kind: ws
url: wss://echo.websocket.events
ws:
  protocols: graphql-transport-ws, mqtt
  message: '{"type":"ping"}'
  messages:
    - {name: ping, value: '{"type":"ping"}'}
```

## Collection and folder settings

`openrest.yaml` starts with `openrest: 1`; both it and `folder.yaml` accept `name`, `headers`, `auth`, `vars`, `scripts`, `tests`, `docs` (the Markdown shown on the collection overview) and `tls`. Folders also have `seq`.

## Environment

```yaml
name: dev
variables:
  - {name: baseUrl, value: 'https://dev.example.com'}
  - {name: token, secret: true}   # value lives in ~/.openrest/secrets.json
```

## Workflow

`workflows/<name>.yaml` has `name`, `description`, `stopOnFail` (written only when false) and `steps`. See [workflows](workflows.md).
