cask "odysseus-source" do
  version "2026.09.05.172112-934d23c0"
  sha256 "65b74c853a54b0ef3019ac8bc5390bb1f3c55d15906200991ee679b568e5185e"

  # Managed by scripts/update-odysseus-cask.rb.
  odysseus_upstream_revision = "934d23c0be29c9721385f34565c0ae2cbd60da04"

  url "https://github.com/odysseus-dev/odysseus/archive/#{odysseus_upstream_revision}.tar.gz"
  name "Odysseus source build"
  desc "Self-hosted AI workspace built from source for macOS"
  homepage "https://github.com/odysseus-dev/odysseus"

  livecheck do
    skip "Version is managed by the Odysseus commit updater."
  end

  depends_on formula: "python@3.13"

  generated_script "install-odysseus-source.sh", content: <<~'SH'
    #!/bin/bash
    set -euo pipefail

    die() {
      printf 'Error: %s\n' "$*" >&2
      exit 1
    }

    user_home="${HOME:-}"
    [ -n "$user_home" ] || die "HOME is not set"
    [ "$#" -ge 1 ] || die "Missing cask staging path"
    staged_root="$1"
    [ -d "$staged_root" ] || die "Cask staging path does not exist: $staged_root"

    state_root="$user_home/Library/Application Support/Medovukha/Odysseus"
    source_root="$state_root/source"
    data_root="$state_root/data"
    config_file="$state_root/.env"
    venv_root="$state_root/venv"
    target_app="$user_home/Applications/Odysseus-local.app"
    backup_root="$state_root/backups"
    lock_dir="$state_root/install.lock"
    mkdir -p "$state_root" "$data_root" "$backup_root"

    if [ -e "$lock_dir" ]; then
      lock_pid="$(/usr/bin/sed -n '1p' "$lock_dir/pid" 2>/dev/null || true)"
      case "$lock_pid" in
        ''|*[!0-9]*) lock_pid='' ;;
      esac
      if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        die "Another Odysseus source install is running (PID $lock_pid)"
      fi
      /bin/rm -rf "$lock_dir"
    fi
    mkdir "$lock_dir" || die "Could not acquire install lock: $lock_dir"
    printf '%s\n' "$$" > "$lock_dir/pid"

    incoming_root=""
    app_build=""
    app_tmp=""
    source_backup=""
    app_backup=""
    source_installed=0
    app_installed=0

    rollback() {
      if [ -n "$app_backup" ] && [ -e "$app_backup" ]; then
        if [ -e "$target_app" ] || [ -L "$target_app" ]; then
          /bin/rm -rf "$target_app"
        fi
        /bin/mv "$app_backup" "$target_app" 2>/dev/null || true
      elif [ "$app_installed" -eq 1 ] && { [ -e "$target_app" ] || [ -L "$target_app" ]; }; then
        /bin/rm -rf "$target_app"
      fi

      if [ -n "$source_backup" ] && [ -e "$source_backup" ]; then
        if [ -e "$source_root" ] || [ -L "$source_root" ]; then
          /bin/rm -rf "$source_root"
        fi
        /bin/mv "$source_backup" "$source_root" 2>/dev/null || true
      elif [ "$source_installed" -eq 1 ] && { [ -e "$source_root" ] || [ -L "$source_root" ]; }; then
        /bin/rm -rf "$source_root"
      fi
    }

    cleanup() {
      status="$?"
      if [ "$status" -ne 0 ]; then
        rollback
      fi
      if [ -n "$incoming_root" ] && [ -e "$incoming_root" ]; then
        /bin/rm -rf "$incoming_root"
      fi
      if [ -n "$app_build" ] && [ -e "$app_build" ]; then
        /bin/rm -rf "$app_build"
      fi
      if [ -n "$app_tmp" ] && [ -e "$app_tmp" ]; then
        /bin/rm -rf "$app_tmp"
      fi
      /bin/rm -f "$lock_dir/pid"
      /bin/rmdir "$lock_dir" 2>/dev/null || true
      exit "$status"
    }
    trap cleanup EXIT INT TERM

    for required_command in brew curl ditto find mkdir mv rm sed shasum tar; do
      command -v "$required_command" >/dev/null 2>&1 || die "Required command not found: $required_command"
    done

    source_from_archive="$(find "$staged_root" -mindepth 1 -maxdepth 1 -type d -name 'odysseus-*' -print -quit)"
    [ -n "$source_from_archive" ] || die "Odysseus source directory not found in $staged_root"
    [ -f "$source_from_archive/app.py" ] || die "Odysseus app.py not found in $source_from_archive"
    [ -f "$source_from_archive/setup.py" ] || die "Odysseus setup.py not found in $source_from_archive"
    [ -f "$source_from_archive/requirements.txt" ] || die "Odysseus requirements.txt not found in $source_from_archive"

    python_prefix="$(brew --prefix python@3.13 2>/dev/null || true)"
    python_bin="$python_prefix/bin/python3.13"
    [ -x "$python_bin" ] || die "Homebrew python@3.13 is installed but python3.13 was not found"
    "$python_bin" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 11) else 1)' || \
      die "Odysseus requires Python 3.11 or newer"

    if [ ! -e "$config_file" ]; then
      umask 077
      {
        printf '# Odysseus source cask settings.\n'
        printf '# Keep AUTH_ENABLED=true when exposing the service beyond localhost.\n'
        printf 'ODYSSEUS_DATA_DIR=%s\n' "$data_root"
        printf 'APP_BIND=127.0.0.1\n'
        printf 'APP_PORT=7860\n'
        printf 'AUTH_ENABLED=true\n'
      } > "$config_file"
    fi
    [ -f "$config_file" ] || die "Odysseus settings path is not a regular file: $config_file"
    chmod 600 "$config_file"

    incoming_root="$state_root/.source-$$"
    /bin/rm -rf "$incoming_root"
    ditto "$source_from_archive" "$incoming_root"
    if [ -e "$incoming_root/.env" ] || [ -L "$incoming_root/.env" ]; then
      /bin/rm -rf "$incoming_root/.env"
    fi
    ln -s "$config_file" "$incoming_root/.env"

    venv_python="$venv_root/bin/python"
    if [ ! -x "$venv_python" ] || ! "$venv_python" -m pip --version >/dev/null 2>&1; then
      /bin/rm -rf "$venv_root"
      "$python_bin" -m venv "$venv_root"
      venv_python="$venv_root/bin/python"
    fi
    [ -x "$venv_python" ] || die "Could not create the Odysseus Python environment"

    requirements_hash="$(shasum -a 256 "$incoming_root/requirements.txt" | awk '{print $1}')"
    requirements_marker="$state_root/.requirements.sha256"
    installed_requirements_hash="$(/usr/bin/sed -n '1p' "$requirements_marker" 2>/dev/null || true)"
    if [ "$requirements_hash" != "$installed_requirements_hash" ]; then
      "$venv_python" -m pip install --upgrade pip
      "$venv_python" -m pip install -r "$incoming_root/requirements.txt"
      printf '%s\n' "$requirements_hash" > "$requirements_marker.tmp.$$"
      /bin/mv "$requirements_marker.tmp.$$" "$requirements_marker"
    fi

    (
      cd "$incoming_root"
      ODYSSEUS_DATA_DIR="$data_root" \
        ODYSSEUS_SKIP_ADMIN_PROMPT=1 \
        ODYSSEUS_SKIP_RUN_HINT=1 \
        "$venv_python" setup.py
    )

    app_build="$state_root/.Odysseus-local.app.$$"
    mkdir -p "$app_build/Contents/MacOS" "$app_build/Contents/Resources"

    cat > "$app_build/Contents/Info.plist" <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleName</key>
        <string>Odysseus-local</string>
        <key>CFBundleDisplayName</key>
        <string>Odysseus (Local)</string>
        <key>CFBundleIdentifier</key>
        <string>com.medovukha.odysseus-local</string>
        <key>CFBundleVersion</key>
        <string>1</string>
        <key>CFBundleShortVersionString</key>
        <string>1.0</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleExecutable</key>
        <string>Odysseus-local</string>
        <key>LSMinimumSystemVersion</key>
        <string>11.0</string>
        <key>NSHighResolutionCapable</key>
        <true/>
        <key>LSUIElement</key>
        <false/>
    </dict>
    </plist>
    PLIST

    cat > "$app_build/Contents/MacOS/Odysseus-local" <<'LAUNCHER'
    #!/bin/bash
    set -u

    STATE_ROOT="$HOME/Library/Application Support/Medovukha/Odysseus"
    SOURCE_ROOT="$STATE_ROOT/source"
    DATA_ROOT="$STATE_ROOT/data"
    VENV_ROOT="$STATE_ROOT/venv"
    CONFIG_FILE="$STATE_ROOT/.env"
    LOG_FILE="$STATE_ROOT/logs/odysseus-app.log"
    PORT="${ODYSSEUS_PORT:-7860}"
    HOST="${ODYSSEUS_HOST:-127.0.0.1}"

    if [ -f "$CONFIG_FILE" ]; then
      configured_port="$(/usr/bin/sed -n 's/^[[:space:]]*APP_PORT[[:space:]]*=[[:space:]]*//p' "$CONFIG_FILE" | /usr/bin/tail -n 1)"
      configured_host="$(/usr/bin/sed -n 's/^[[:space:]]*APP_BIND[[:space:]]*=[[:space:]]*//p' "$CONFIG_FILE" | /usr/bin/tail -n 1)"
      case "$configured_port" in
        ''|*[!0-9]*) ;;
        *) [ -n "${ODYSSEUS_PORT:-}" ] || PORT="$configured_port" ;;
      esac
      case "$configured_host" in
        '') ;;
        *) [ -n "${ODYSSEUS_HOST:-}" ] || HOST="$configured_host" ;;
      esac
    fi

    URL_HOST="$HOST"
    if [ "$URL_HOST" = "0.0.0.0" ] || [ "$URL_HOST" = "::" ]; then
      URL_HOST="127.0.0.1"
    fi
    URL="http://$URL_HOST:$PORT"
    PYTHON="$VENV_ROOT/bin/python"

    notify() {
      /usr/bin/osascript -e "display notification \"$1\" with title \"Odysseus\"" >/dev/null 2>&1 || true
    }

    die_gui() {
      /usr/bin/osascript -e "display dialog \"$1\" with title \"Odysseus\" buttons {\"OK\"} default button 1 with icon stop" >/dev/null 2>&1 || true
      exit 1
    }

    [ -x "$PYTHON" ] || die_gui "Odysseus is not set up yet. Re-run brew upgrade --cask odysseus-source."
    [ -f "$SOURCE_ROOT/app.py" ] || die_gui "Odysseus source directory is missing: $SOURCE_ROOT"
    mkdir -p "$(dirname "$LOG_FILE")"

    open_ui() {
      local browser base executable binary
      for browser in "Google Chrome" "Microsoft Edge" "Brave Browser" "Chromium"; do
        for base in "/Applications" "$HOME/Applications"; do
          if [ -d "$base/$browser.app" ]; then
            executable="$(/usr/bin/defaults read "$base/$browser.app/Contents/Info" CFBundleExecutable 2>/dev/null || true)"
            binary="$base/$browser.app/Contents/MacOS/$executable"
            if [ -x "$binary" ]; then
              "$binary" --app="$URL" --new-window >/dev/null 2>&1 &
              return 0
            fi
          fi
        done
      done
      /usr/bin/open "$URL"
    }

    if /usr/bin/curl -s -o /dev/null --max-time 2 "$URL"; then
      open_ui
      exit 0
    fi

    notify "Starting…"
    cd "$SOURCE_ROOT" || die_gui "Odysseus source directory is missing: $SOURCE_ROOT"
    export ODYSSEUS_DATA_DIR="$DATA_ROOT"
    export APP_PORT="$PORT"
    export APP_BIND="$HOST"
    "$PYTHON" -m uvicorn app:app --host "$HOST" --port "$PORT" >> "$LOG_FILE" 2>&1 &
    server_pid=$!

    cleanup_server() {
      kill "$server_pid" 2>/dev/null || true
    }
    trap cleanup_server EXIT INT TERM

    ready=0
    for _ in $(seq 1 120); do
      /usr/bin/curl -s -o /dev/null --max-time 2 "$URL" && { ready=1; break; }
      kill -0 "$server_pid" 2>/dev/null || die_gui "Odysseus failed to start. Log: $LOG_FILE"
      sleep 1
    done

    if [ "$ready" = "1" ]; then
      open_ui
    else
      notify "Odysseus is taking a while — open $URL when it finishes starting."
    fi
    wait "$server_pid"
    LAUNCHER
    chmod 0755 "$app_build/Contents/MacOS/Odysseus-local"

    icon_source="$incoming_root/assets/branding/odysseus.jpg"
    if [ -f "$icon_source" ] && command -v sips >/dev/null 2>&1; then
      icon_tmp="$(mktemp -d)"
      sips -c 720 720 "$icon_source" --out "$icon_tmp/square.png" >/dev/null 2>&1 || cp "$icon_source" "$icon_tmp/square.png"
      sips -z 512 512 "$icon_tmp/square.png" --out "$icon_tmp/icon.png" >/dev/null 2>&1 || true
      if [ -f "$icon_tmp/icon.png" ]; then
        sips -s format icns "$icon_tmp/icon.png" --out "$app_build/Contents/Resources/odysseus.icns" >/dev/null 2>&1 || true
      fi
      /bin/rm -rf "$icon_tmp"
    fi

    if [ -e "$source_root" ] || [ -L "$source_root" ]; then
      source_backup="$backup_root/source-$(date -u '+%Y%m%dT%H%M%SZ')-$$"
      /bin/mv "$source_root" "$source_backup"
    fi
    /bin/mv "$incoming_root" "$source_root"
    incoming_root=''
    source_installed=1

    mkdir -p "$(dirname "$target_app")"
    if [ -L "$target_app" ]; then
      die "Refusing to replace symlink: $target_app"
    fi
    app_tmp="$user_home/Applications/.Odysseus-local.app.$$"
    /bin/rm -rf "$app_tmp"
    ditto "$app_build" "$app_tmp"
    xattr -cr "$app_tmp" >/dev/null 2>&1 || true
    if [ -e "$target_app" ]; then
      app_backup="$backup_root/Odysseus-local.app-$(date -u '+%Y%m%dT%H%M%SZ')-$$"
      /bin/mv "$target_app" "$app_backup"
    fi
    /bin/mv "$app_tmp" "$target_app"
    app_tmp=''
    app_installed=1

    if [ -n "$source_backup" ] && [ -e "$source_backup" ]; then
      /bin/rm -rf "$source_backup"
      source_backup=''
    fi
    if [ -n "$app_backup" ] && [ -e "$app_backup" ]; then
      /bin/rm -rf "$app_backup"
      app_backup=''
    fi

    printf 'Installed Odysseus source build at %s\n' "$target_app"
    printf 'Persistent data and settings: %s\n' "$state_root"
  SH

  installer script: {
    executable: "install-odysseus-source.sh",
    args:       [staged_path],
  }

  uninstall trash: "#{Dir.home}/Applications/Odysseus-local.app"
  zap trash: "#{Dir.home}/Library/Application Support/Medovukha/Odysseus"
end
