# Telegram MCP source formula

This tap packages the `chigwell/telegram-mcp` GitHub source tree as
`telegram-mcp-source`. It intentionally does not install the unrelated PyPI
project also named `telegram-mcp`.

Install it with:

~~~sh
brew install EndorFlem/medovukha/telegram-mcp-source
~~~

The formula has one Homebrew dependency: `uv`. Python dependencies are synced
on the first invocation into an isolated user-owned environment. This keeps
the formula small and keeps Telegram credentials/session files out of the
Homebrew Cellar.

The runtime state directory is:

~~~text
~/.local/state/telegram-mcp/
~~~

You can override it with `TELEGRAM_MCP_STATE_DIR`. The directory may contain a
`.env` file with:

~~~dotenv
TELEGRAM_API_ID=...
TELEGRAM_API_HASH=...
TELEGRAM_SESSION_STRING=...
TELEGRAM_EXPOSED_TOOLS=read-only
~~~

Generate a session interactively:

~~~sh
telegram-mcp-generate-session --qr
~~~

The MCP server itself is available as:

~~~sh
telegram-mcp
~~~

For a stdio MCP client, use the absolute executable path returned by:

~~~sh
command -v telegram-mcp
~~~

For shared HTTP mode, set these variables in the state `.env` file before
starting the server:

~~~dotenv
MCP_TRANSPORT=http
MCP_HOST=127.0.0.1
MCP_PORT=8765
~~~

Then register `http://127.0.0.1:8765/mcp` in the MCP client. Keep it bound to
localhost unless you deliberately configure the upstream host/origin security
settings.
