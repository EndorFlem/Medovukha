class TelegramMcpSource < Formula
  desc "Telegram MCP server powered by Telethon"
  homepage "https://github.com/chigwell/telegram-mcp"
  # Managed by scripts/update-telegram-mcp-formula.rb.
  telegram_mcp_upstream_tag = "v3.2.47"
  # telegram_mcp_upstream_revision = "45cce7e3dbf50655645f48d5f78d8a84aec6aa8f"

  url "https://github.com/chigwell/telegram-mcp/archive/refs/tags/#{telegram_mcp_upstream_tag}.tar.gz"
  sha256 "d922424cffea475e8f7d1b46eeab6351e7251e94188bf158c1c8a439261b79b5"
  license "Apache-2.0"

  # The project must come from this GitHub source archive. The PyPI project
  # named telegram-mcp is unrelated and is explicitly rejected upstream.
  livecheck do
    skip "Version is managed by the Telegram MCP release updater."
  end

  depends_on "uv"

  def install
    libexec.install Dir["*"]

    runner = <<~SH
      #!/bin/bash
      set -euo pipefail

      source_root="#{opt_libexec}"
      state_root="${TELEGRAM_MCP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/telegram-mcp}"
      venv_root="$state_root/venv"
      revision_file="$state_root/installed-revision"
      lock_dir="$state_root/sync.lock"
      command_name="${1:-}"
      shift || true

      case "$command_name" in
        telegram-mcp|telegram-mcp-generate-session) ;;
        *)
          echo "Usage: telegram-mcp-runner <telegram-mcp|telegram-mcp-generate-session> [args...]" >&2
          exit 64
          ;;
      esac

      mkdir -p "$state_root"

      release_lock() {
        /bin/rm -f "$lock_dir/pid"
        /bin/rmdir "$lock_dir" 2>/dev/null || true
      }

      sync_if_needed() {
        while ! mkdir "$lock_dir" 2>/dev/null; do
          lock_pid="$(/usr/bin/sed -n '1p' "$lock_dir/pid" 2>/dev/null || true)"
          case "$lock_pid" in
            ''|*[!0-9]*) lock_pid='' ;;
          esac
          if [ -z "$lock_pid" ] || ! kill -0 "$lock_pid" 2>/dev/null; then
            /bin/rm -rf "$lock_dir"
            continue
          fi
          sleep 1
        done
        printf '%s\n' "$$" > "$lock_dir/pid"
        trap release_lock EXIT INT TERM

        installed_revision="$(/usr/bin/sed -n '1p' "$revision_file" 2>/dev/null || true)"
        if [ ! -x "$venv_root/bin/$command_name" ] || [ "$installed_revision" != "#{version}" ]; then
          temporary_venv="$state_root/.venv.tmp.$$"
          /bin/rm -rf "$temporary_venv"
          UV_PROJECT_ENVIRONMENT="$temporary_venv" uv sync \
            --project "$source_root" \
            --frozen \
            --no-dev \
            --python 3.13 >&2

          previous_venv="$state_root/.venv.previous.$$"
          if [ -e "$venv_root" ]; then
            /bin/mv "$venv_root" "$previous_venv"
          fi
          /bin/mv "$temporary_venv" "$venv_root"
          printf '%s\n' "#{version}" > "$revision_file.tmp.$$"
          /bin/mv "$revision_file.tmp.$$" "$revision_file"
          if [ -e "$previous_venv" ]; then
            /bin/rm -rf "$previous_venv"
          fi
        fi
      }

      sync_if_needed
      release_lock
      trap - EXIT INT TERM

      cd "$state_root"
      exec "$venv_root/bin/$command_name" "$@"
    SH
    (libexec/"telegram-mcp-runner").write runner
    chmod 0755, libexec/"telegram-mcp-runner"

    %w[telegram-mcp telegram-mcp-generate-session].each do |command_name|
      (bin/command_name).write <<~SH
        #!/bin/bash
        exec "#{opt_libexec}/telegram-mcp-runner" "#{command_name}" "$@"
      SH
      chmod 0755, bin/command_name
    end
  end

  def caveats
    <<~EOS
      Telegram MCP state, session files, and the user .env file live under:
        #{ENV["XDG_STATE_HOME"] || "~/.local/state"}/telegram-mcp

      Create the .env file there with TELEGRAM_API_ID, TELEGRAM_API_HASH, and
      TELEGRAM_SESSION_STRING, or pass those variables from your MCP client.
      For a safer initial setup, consider TELEGRAM_EXPOSED_TOOLS=read-only.

      Generate a session interactively with:
        telegram-mcp-generate-session --qr
    EOS
  end

  test do
    assert_path_exists libexec/"pyproject.toml"
    assert_path_exists bin/"telegram-mcp"
    assert_path_exists bin/"telegram-mcp-generate-session"
    assert_match "chigwell/telegram-mcp", File.read(libexec/"README.md")
  end
end
