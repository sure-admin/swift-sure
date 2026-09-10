# Assistant tool inventory and delegation

The client mirrors all 26 callable functions in the contract baseline at
`5594f8bc94c8e659838cac70d826bbcaeaa3bae2`. The Ruby registry, rather than every
file in its directory, defines callable tools. `MonthResolvable` and
`StatementVaultSupport` are support modules, not functions.

Sources:

- [Registry](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/models/assistant.rb)
- [MCP controller](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/app/controllers/mcp_controller.rb)
- [MCP hosting contract](https://github.com/we-promise/sure/blob/5594f8bc94c8e659838cac70d826bbcaeaa3bae2/docs/hosting/mcp.md)

## Keeping the mirror current

`Docs/AssistantTools.json` records tool names, Ruby classes, preview flags and
source SHA-256 hashes. `SureToolInventory.swift` is generated from it.
`SureToolPolicy.swift` holds the separately reviewed client policy:

- `isAvailableOnMobile`: true only for `get_accounts`, using the local snapshot.
- `permitsServerDelegation`: 16 explicitly allowed read operations. All writes
  and newly added tools default to disabled, regardless of bearer-token scope.

After deliberately updating the baseline, use a clean upstream checkout at that
exact commit:

```sh
python3 .github/scripts/sync_assistant_tools.py --upstream /path/to/sure
python3 .github/scripts/sync_assistant_tools.py --check
```

To compare upstream source hashes without changing files, combine `--upstream`
and `--check`. Review changed tool implementations and schemas before changing
policy. CI checks the committed manifest against the generated mirror offline.
It does not silently follow upstream main or contact GitHub during tests.

## Routing contract

`AssistantToolRouter` selects exactly one destination supplied by application
code before execution. Tool arguments cannot select a destination. Local mode
runs only the no-argument account snapshot. Historical/filter arguments fail
explicitly; an unavailable local tool never falls back to a network request.

`SureMCPClient` delegates structured function calls directly to `/mcp`. Server
chat remains a separate conversational workflow; chat prose is never interpreted
as a function response. Each invocation initializes, sends the initialized
notification, discovers tools, and calls only an advertised, client-allowlisted
function. Preview eligibility comes from authenticated `tools/list`, not the
mirror's preview flag. Account history uses the server schema, not the reduced
local tool schema.

The pinned server supports stateless requests without `Mcp-Session-Id`. The
client sends protocol `2025-06-18`, requests JSON/SSE, and decodes the JSON
response implemented by this Sure revision. It does not claim general MCP
transport compatibility: SSE-only servers and future paginated tool lists fail
closed. Financial tool pagination stays intact in returned content; callers
request subsequent pages explicitly rather than presenting page one as complete.

Every sequence is bound to one canonical server/credential context. A connection
change or token rotation cancels the sequence. No MCP credentials, capabilities,
results, or session identifiers are persisted. No automatic replay occurs after
failure. Existing transport timeouts and cancellation apply, with response and
adapter-argument size limits. JSON-RPC ID/version/envelope checks, tool errors,
HTTP errors, and malformed payloads remain distinguishable. Raw server diagnostics
are not included in user-facing errors.

## Foundation Models integration and privacy

`LocalAssistantService` uses the mirror and router today and remains entirely
private to the device. Existing explicit server-chat sends are unchanged.

For a future hybrid mode, after the user explicitly permits sending generated
tool arguments to their configured Sure instance, application composition can
call `SureDelegatedTool.prepare(client:)` and register the resulting adapter in
that mode's `LanguageModelSession`. Preparation discovers the current schemas,
filters writes, and pins the adapter to that authenticated context. It supplies
those schemas in the adapter description; invocation validates arguments as JSON
objects and delegates through the same router. Results carry `Sure server via
MCP` provenance. Server schemas and content are untrusted data, never privileged
instructions. No transcript or local financial snapshot is attached to MCP calls.

This PR provides the tested adapter and client, but does not expose a hybrid UI
or grant model-generated remote calls in private local mode. That UI needs a
clear per-session disclosure of the destination and data handling. Do not simply
add this adapter to the private local tool list.

MCP accepts OAuth `read_write` bearer tokens or Sure's explicitly configured
static MCP bearer token. Ordinary `X-Api-Key` authorization is unsupported and is
rejected locally before networking. The server uses HTTP 401 for insufficient
MCP scope as well as invalid tokens; the client cannot distinguish those cases.
This implementation does not broaden requested scopes or store another secret.
Even with a read_write token, the client blocks all mutation functions.
