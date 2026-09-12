cask "odysseus-source" do
  # The packaging suffix makes the Docker-only migration visible to Homebrew
  # even when the upstream commit has not changed yet.
  version "2026.09.12.000001-934d23c0-docker"
  sha256 "65b74c853a54b0ef3019ac8bc5390bb1f3c55d15906200991ee679b568e5185e"

  # Managed by scripts/update-odysseus-cask.rb.
  odysseus_upstream_revision = "934d23c0be29c9721385f34565c0ae2cbd60da04"

  url "https://github.com/odysseus-dev/odysseus/archive/#{odysseus_upstream_revision}.tar.gz"
  name "Odysseus source build"
  desc "Self-hosted AI workspace run with Docker Compose"
  homepage "https://github.com/odysseus-dev/odysseus"

  livecheck do
    skip "Version is managed by the Odysseus commit updater."
  end

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
    logs_root="$state_root/logs"
    config_file="$state_root/.env"
    target_app="$user_home/Applications/Odysseus-local.app"
    backup_root="$state_root/backups"
    lock_dir="$state_root/install.lock"
    mkdir -p "$state_root" "$data_root" "$logs_root" "$backup_root"

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

    for required_command in ditto find mkdir mv rm sed tar; do
      command -v "$required_command" >/dev/null 2>&1 || die "Required command not found: $required_command"
    done

    source_from_archive="$(find "$staged_root" -mindepth 1 -maxdepth 1 -type d -name 'odysseus-*' -print -quit)"
    [ -n "$source_from_archive" ] || die "Odysseus source directory not found in $staged_root"
    [ -f "$source_from_archive/app.py" ] || die "Odysseus app.py not found in $source_from_archive"
    [ -f "$source_from_archive/docker-compose.yml" ] || die "Odysseus docker-compose.yml not found in $source_from_archive"
    [ -f "$source_from_archive/.env.example" ] || die "Odysseus .env.example not found in $source_from_archive"

    set_env_default() {
      key="$1"
      value="$2"
      legacy_value="${3:-}"
      if ! /usr/bin/grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$config_file"; then
        printf '%s=%s\n' "$key" "$value" >> "$config_file"
        return 0
      fi
      [ -n "$legacy_value" ] || return 0

      env_tmp="$config_file.tmp.$$"
      /usr/bin/awk -v key="$key" -v value="$value" -v legacy="$legacy_value" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
          current = $0
          sub("^[[:space:]]*" key "[[:space:]]*=", "", current)
          sub("^[[:space:]]*", "", current)
          if (current == legacy) print key "=" value
          else print
          next
        }
        { print }
      ' "$config_file" > "$env_tmp"
      /bin/mv "$env_tmp" "$config_file"
    }

    if [ ! -e "$config_file" ]; then
      umask 077
      : > "$config_file"
    fi
    [ -f "$config_file" ] || die "Odysseus settings path is not a regular file: $config_file"
    # Keep a user's custom port, but migrate the old native cask default 7860
    # to the Docker Compose default 7000.
    set_env_default "COMPOSE_PROJECT_NAME" "medovukha-odysseus"
    set_env_default "APP_BIND" "127.0.0.1"
    set_env_default "APP_PORT" "7000" "7860"
    set_env_default "APP_DATA_DIR" "\"$data_root\""
    set_env_default "APP_LOGS_DIR" "\"$logs_root\""
    set_env_default "AUTH_ENABLED" "true"
    set_env_default "LOCALHOST_BYPASS" "false"
    set_env_default "ALLOWED_ORIGINS" "http://localhost:7000,http://127.0.0.1:7000"
    set_env_default "ODYSSEUS_TTS_CACHE_MAX_BYTES" ""
    chmod 600 "$config_file"

    incoming_root="$state_root/.source-$$"
    /bin/rm -rf "$incoming_root"
    ditto "$source_from_archive" "$incoming_root"
    if [ -e "$incoming_root/.env" ] || [ -L "$incoming_root/.env" ]; then
      /bin/rm -rf "$incoming_root/.env"
    fi
    ln -s "$config_file" "$incoming_root/.env"

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
        <string>Odysseus (Docker)</string>
        <key>CFBundleIdentifier</key>
        <string>com.medovukha.odysseus-local</string>
        <key>CFBundleVersion</key>
        <string>2</string>
        <key>CFBundleShortVersionString</key>
        <string>2.0</string>
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

    export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
    STATE_ROOT="$HOME/Library/Application Support/Medovukha/Odysseus"
    SOURCE_ROOT="$STATE_ROOT/source"
    CONFIG_FILE="$STATE_ROOT/.env"
    LOG_FILE="$STATE_ROOT/logs/docker-compose-launch.log"

    show_error() {
      /usr/bin/osascript -e "display dialog \"$1\" with title \"Odysseus Docker\" buttons {\"OK\"} default button 1 with icon stop" >/dev/null 2>&1 || true
      exit 1
    }

    [ -f "$CONFIG_FILE" ] || show_error "Odysseus settings are missing: $CONFIG_FILE"
    [ -d "$SOURCE_ROOT" ] || show_error "Odysseus source directory is missing: $SOURCE_ROOT"
    export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
    command -v docker >/dev/null 2>&1 || show_error "Docker CLI is not installed. Install Docker Desktop first."
    docker compose version >/dev/null 2>&1 || show_error "Docker Compose is not available in the Docker CLI."
    if ! docker info >/dev/null 2>&1; then
      if [ -d "/Applications/Docker.app" ]; then
        /usr/bin/open -g -a Docker >/dev/null 2>&1 || show_error "Could not start Docker Desktop."
        for _ in $(seq 1 60); do
          docker info >/dev/null 2>&1 && break
          sleep 1
        done
      fi
    fi
    docker info >/dev/null 2>&1 || show_error "Docker Desktop is not running. Start Docker Desktop and launch Odysseus-local again."

    mkdir -p "$(dirname "$LOG_FILE")"
    port="$(/usr/bin/sed -n 's/^[[:space:]]*APP_PORT[[:space:]]*=[[:space:]]*\"*\([0-9][0-9]*\)\"*.*/\1/p' "$CONFIG_FILE" | /usr/bin/tail -n 1)"
    port="${port:-7000}"
    running_container="$(docker compose \
      --project-directory "$SOURCE_ROOT" \
      --env-file "$CONFIG_FILE" \
      ps --status running -q odysseus 2>/dev/null || true)"
    effective_port="$port"
    if [ -z "$running_container" ] && /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      fallback_port=$((port + 1))
      while /usr/sbin/lsof -nP -iTCP:"$fallback_port" -sTCP:LISTEN >/dev/null 2>&1; do
        fallback_port=$((fallback_port + 1))
      done

      env_tmp="$CONFIG_FILE.tmp.$$"
      /usr/bin/awk -v old_port="$port" -v new_port="$fallback_port" '
        $0 ~ "^[[:space:]]*APP_PORT[[:space:]]*=" {
          print "APP_PORT=" new_port
          port_seen = 1
          next
        }
        $0 ~ "^[[:space:]]*ALLOWED_ORIGINS[[:space:]]*=" {
          value = $0
          sub("^[[:space:]]*ALLOWED_ORIGINS[[:space:]]*=", "", value)
          gsub("http://localhost:" old_port, "http://localhost:" new_port, value)
          gsub("http://127\\.0\\.0\\.1:" old_port, "http://127.0.0.1:" new_port, value)
          if (index(value, "http://localhost:" new_port) == 0) value = value ",http://localhost:" new_port
          if (index(value, "http://127.0.0.1:" new_port) == 0) value = value ",http://127.0.0.1:" new_port
          print "ALLOWED_ORIGINS=" value
          origins_seen = 1
          next
        }
        { print }
        END {
          if (!port_seen) print "APP_PORT=" new_port
          if (!origins_seen) print "ALLOWED_ORIGINS=http://localhost:" new_port ",http://127.0.0.1:" new_port
        }
      ' "$CONFIG_FILE" > "$env_tmp" && /bin/mv "$env_tmp" "$CONFIG_FILE"

      effective_port="$fallback_port"
    fi

    if ! docker compose \
      --project-directory "$SOURCE_ROOT" \
      --env-file "$CONFIG_FILE" \
      up -d --build > "$LOG_FILE" 2>&1; then
      /usr/bin/osascript -e "display dialog \"Docker Compose could not start Odysseus.\n\nLog: $LOG_FILE\" with title \"Odysseus Docker\" buttons {\"OK\"} default button 1 with icon stop" >/dev/null 2>&1 || true
      exit 1
    fi
    if [ "$effective_port" != "$port" ]; then
      printf 'Port %s is occupied; using fallback port %s\n' "$port" "$effective_port" >> "$LOG_FILE"
      /usr/bin/osascript -e "display notification \"Port $port is busy; Odysseus is running at http://127.0.0.1:$effective_port\" with title \"Odysseus Docker\"" >/dev/null 2>&1 || true
    fi
    exit 0
    LAUNCHER
    chmod 0755 "$app_build/Contents/MacOS/Odysseus-local"

    icon_source="$incoming_root/assets/branding/odysseus.jpg"
    if [ -f "$icon_source" ] && command -v sips >/dev/null 2>&1; then
      icon_tmp="$(mktemp -d)"
      sips -c 720 720 "$icon_source" --out "$icon_tmp/square.png" >/dev/null 2>&1 || /bin/cp "$icon_source" "$icon_tmp/square.png"
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
    /usr/bin/codesign --force --deep --sign - "$app_tmp" || die "Could not ad-hoc sign $target_app"
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

    printf 'Installed Odysseus Docker source build at %s\n' "$target_app"
    printf 'Docker project and persistent data: %s\n' "$state_root"
  SH

  installer script: {
    executable: "install-odysseus-source.sh",
    args:       [staged_path],
  }

  uninstall trash: "#{Dir.home}/Applications/Odysseus-local.app"
  zap trash: "#{Dir.home}/Library/Application Support/Medovukha/Odysseus"
end
