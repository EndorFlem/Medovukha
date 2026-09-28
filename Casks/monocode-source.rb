cask "monocode-source" do
  version "2026.09.28.181221-6ffc995"
  sha256 "b1a53b7f8e6be8c7e067e345cce3210073f768f45efdfdc5e6e190ae10940c51"

  # Managed by scripts/update-monocode-source-cask.rb.
  monocode_upstream_revision = "6ffc99589be087d16bb6d764afdc3502e5046750"
  monocode_patch_sha256 = "c816097d06112bfd065132f82556fa01e48f7aa4b8dd91d6fd15dcc497d6af77"

  url "https://github.com/hardbeat920/monocode/archive/#{monocode_upstream_revision}.tar.gz"
  name "MonoCode source build"
  desc "Desktop GUI for coding agents with OMP RPC v2 model discovery"
  homepage "https://github.com/hardbeat920/monocode"

  livecheck do
    skip "Version is managed by the MonoCode source commit updater."
  end

  depends_on macos: :sequoia
  depends_on arch: :arm64
  depends_on formula: "node"
  depends_on formula: "rust"
  conflicts_with cask: "monocode"

  resource "monocode-omp-rpc-v2.patch" do
    url "https://raw.githubusercontent.com/EndorFlem/Medovukha/main/patches/monocode-omp-rpc-v2.patch"
    sha256 monocode_patch_sha256
  end

  generated_script "install-monocode-source.sh", content: <<~'SH'
    #!/bin/bash
    set -euo pipefail

    die() {
      printf 'Error: %s\n' "$*" >&2
      exit 1
    }

    user_home="${HOME:-}"
    [ -n "$user_home" ] || die "HOME is not set"
    [ "$#" -ge 2 ] || die "Missing MonoCode source or patch staging path"
    staged_root="$1"
    patch_path="$2"
    [ -d "$staged_root" ] || die "MonoCode source staging path does not exist: $staged_root"
    [ -f "$patch_path" ] || die "MonoCode OMP patch does not exist: $patch_path"

    state_root="$user_home/Library/Application Support/Medovukha/MonoCode"
    backup_root="$state_root/backups"
    target_app="$user_home/Applications/MonoCode-local.app"
    lock_dir="$state_root/install.lock"
    mkdir -p "$state_root" "$backup_root" "$user_home/Applications"

    if [ -e "$lock_dir" ]; then
      lock_pid="$(/usr/bin/sed -n '1p' "$lock_dir/pid" 2>/dev/null || true)"
      case "$lock_pid" in
        ''|*[!0-9]*) lock_pid='' ;;
      esac
      if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        die "Another MonoCode source build is running (PID $lock_pid)"
      fi
      /bin/rm -rf "$lock_dir"
    fi
    mkdir "$lock_dir" || die "Could not acquire install lock: $lock_dir"
    printf '%s\n' "$$" > "$lock_dir/pid"

    app_tmp=''
    app_backup=''
    rollback() {
      if [ -n "$app_tmp" ] && [ -e "$app_tmp" ]; then
        /bin/rm -rf "$app_tmp"
      fi
      if [ -n "$app_backup" ] && [ -e "$app_backup" ]; then
        if [ -e "$target_app" ] || [ -L "$target_app" ]; then
          /bin/rm -rf "$target_app"
        fi
        /bin/mv "$app_backup" "$target_app" 2>/dev/null || true
      fi
    }

    cleanup() {
      status="$?"
      if [ "$status" -ne 0 ]; then
        rollback
      elif [ -n "$app_backup" ] && [ -e "$app_backup" ]; then
        /bin/rm -rf "$app_backup"
      fi
      /bin/rm -f "$lock_dir/pid"
      /bin/rmdir "$lock_dir" 2>/dev/null || true
      exit "$status"
    }
    trap cleanup EXIT INT TERM

    for required_command in \
      awk cargo cat codesign ditto find git mkdir mv node npm npx patch pgrep rm sed xattr xcodebuild; do
      command -v "$required_command" >/dev/null 2>&1 || die "Required command not found: $required_command"
    done

    if pgrep -x monocode >/dev/null 2>&1; then
      die "MonoCode is running; quit it before replacing the local app"
    fi

    if [ -z "${DEVELOPER_DIR:-}" ] || [ "$DEVELOPER_DIR" = "/Library/Developer/CommandLineTools" ]; then
      if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
      fi
    fi
    xcodebuild -version >/dev/null 2>&1 || \
      die "Full Xcode is required. Set DEVELOPER_DIR to an Xcode developer directory."

    source_root="$(find "$staged_root" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    [ -n "$source_root" ] || die "MonoCode source directory was not found"
    [ -f "$source_root/package.json" ] || die "MonoCode package.json was not found"
    [ -f "$source_root/package-lock.json" ] || die "MonoCode package-lock.json was not found"

    patch -p1 --batch --forward -d "$source_root" < "$patch_path" || \
      die "The pinned OMP RPC patch does not apply to this MonoCode source tree"

    local_config="$source_root/src-tauri/tauri.medovukha.conf.json"
    cat > "$local_config" <<'JSON'
    {
      "bundle": {
        "createUpdaterArtifacts": false
      },
      "plugins": {
        "updater": {
          "pubkey": "",
          "endpoints": []
        }
      }
    }
    JSON

    export CARGO_TERM_COLOR=never
    npm ci --no-audit --no-fund
    npx tauri build --target aarch64-apple-darwin --bundles app --config "$local_config"

    built_app="$(find "$source_root/src-tauri/target" -type d -path '*/bundle/macos/MonoCode.app' -print -quit)"
    [ -n "$built_app" ] || die "MonoCode.app was not produced by the Tauri build"
    [ -x "$built_app/Contents/MacOS/monocode" ] || die "Built MonoCode.app has no executable"

    app_tmp="$user_home/Applications/.MonoCode-local.app.$$"
    /bin/rm -rf "$app_tmp"
    ditto "$built_app" "$app_tmp"
    codesign --force --deep --sign - "$app_tmp" || die "Could not ad-hoc sign MonoCode-local.app"
    xattr -cr "$app_tmp" >/dev/null 2>&1 || true

    if [ -L "$target_app" ]; then
      die "Refusing to replace symlink: $target_app"
    fi
    if [ -e "$target_app" ]; then
      app_backup="$backup_root/MonoCode-local.app-$(date -u '+%Y%m%dT%H%M%SZ')-$$"
      /bin/mv "$target_app" "$app_backup"
    fi
    /bin/mv "$app_tmp" "$target_app"
    app_tmp=''

    printf 'Installed MonoCode source build at %s\n' "$target_app"
  SH

  installer script: {
    executable: "install-monocode-source.sh",
    args:       [staged_path, resource("monocode-omp-rpc-v2.patch").staged_path],
  }

  uninstall trash: "#{Dir.home}/Applications/MonoCode-local.app"
  zap trash: "#{Dir.home}/Library/Application Support/Medovukha/MonoCode"
end
