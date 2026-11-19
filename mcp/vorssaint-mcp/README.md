# Vorssaint MCP

This package connects an MCP client to the separate Vorssaint Developer build. The first tools report feature state, install or uninstall a feature, control Keep Awake, and set macOS appearance.

## Build

From the repository root, run:

```sh
./build.sh --dev
```

The Developer app starts its local bridge when it launches. The MCP server can launch that app on the first tool call if it is not already running.

Install the Node dependencies once:

```sh
cd mcp/vorssaint-mcp
npm ci
```

## Codex configuration

Add this to `~/.codex/config.toml`, replacing the executable and repository paths with their absolute paths on your Mac:

```toml
[mcp_servers.vorssaint]
command = "/absolute/path/to/node"
args = ["/absolute/path/to/vorssaint-utils/mcp/vorssaint-mcp/server.mjs"]

[mcp_servers.vorssaint.env]
VORSSAINT_APP_PATH = "/absolute/path/to/vorssaint-utils/build/stage.noindex/Vorssaint (Developer).app"
VORSSAINT_BUNDLE_ID = "com.vorssaint.utils.dev"
```

Restart Codex after changing its MCP configuration. The server uses stdio for MCP and communicates with the app over a loopback-only TCP socket.

## Local security

The bridge is compiled into the Developer variant only. It binds to `127.0.0.1`, creates a fresh 256-bit token each launch, and writes the endpoint file under the app's Application Support directory with owner-only permissions. The MCP server reads that file and sends only typed requests. The bridge does not expose arbitrary shell execution, clipboard contents, or file reads.

This Developer app has its own settings and macOS permissions, separate from the official Vorssaint installation. Export settings from the official app and import them into the Developer app if you want to carry over your setup.
