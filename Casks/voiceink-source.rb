cask "voiceink-source" do
  version "2026.09.02.184240-8f089cb4"
  sha256 "18a1322c5899fdb43566d839689ea25d31fb5ca013a1306e440b3c0781ea5e68"

  # Managed by scripts/update-voiceink-cask.rb.
  voiceink_upstream_revision = "8f089cb4bf2c9c2f217b0cc0af909d9052ff6288"
  whisper_cpp_revision = "52a939a2a762224e255d366c1182b2af4dd1a032"
  whisper_cpp_sha256 = "6212572f00e887698440dbbf87aef27de6e56dbe73907f6148686ec55d584a19"

  url "https://github.com/Beingpax/VoiceInk/archive/#{voiceink_upstream_revision}.tar.gz"
  name "VoiceInk source build"
  desc "Free local source build of VoiceInk for macOS"
  homepage "https://github.com/Beingpax/VoiceInk"

  livecheck do
    skip "Version is managed by the VoiceInk commit updater."
  end

  depends_on macos: :sequoia
  depends_on arch: :arm64
  depends_on formula: "cmake"
  conflicts_with cask: "voiceink"

  generated_script "install-voiceink-source.sh", content: <<~'SH'
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

    state_root="$user_home/Library/Application Support/VoiceInkTap"
    work_home="$state_root/build"
    target_app="$user_home/Applications/VoiceInk-local.app"
    mkdir -p "$state_root" "$work_home"

    lock_dir="$state_root/install.lock"
    if [ -e "$lock_dir" ]; then
      lock_pid="$(/usr/bin/sed -n '1p' "$lock_dir/pid" 2>/dev/null || true)"
      case "$lock_pid" in
        ''|*[!0-9]*) lock_pid='' ;;
      esac
      if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        die "Another VoiceInk source build is running (PID $lock_pid)"
      fi
      /bin/rm -rf "$lock_dir"
    fi
    mkdir "$lock_dir" || die "Could not acquire install lock: $lock_dir"
    printf '%s\n' "$$" > "$lock_dir/pid"

    cleanup() {
      /bin/rm -f "$lock_dir/pid"
      /bin/rmdir "$lock_dir" 2>/dev/null || true
    }
    trap cleanup EXIT INT TERM

    for required_command in git make cmake xcodebuild swift curl tar shasum ditto xattr find awk sed pgrep; do
      command -v "$required_command" >/dev/null 2>&1 || die "Required command not found: $required_command"
    done

    if [ -z "${DEVELOPER_DIR:-}" ] || [ "$DEVELOPER_DIR" = "/Library/Developer/CommandLineTools" ]; then
      if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
      fi
    fi
    xcodebuild -version >/dev/null 2>&1 || die "Full Xcode is required. Set DEVELOPER_DIR to an Xcode developer directory."

    source_root=''
    if [ -f "$staged_root/Makefile" ]; then
      source_root="$staged_root"
    else
      source_root="$(find "$staged_root" -mindepth 1 -maxdepth 1 -type d -name 'VoiceInk-*' -print -quit)"
    fi
    [ -n "$source_root" ] && [ -f "$source_root/Makefile" ] || die "VoiceInk source directory not found in $staged_root"

    export HOME="$work_home"
    whisper_parent="$HOME/VoiceInk-Dependencies"
    whisper_root="$whisper_parent/whisper.cpp"
    whisper_framework="$whisper_root/build-apple/whisper.xcframework"
    whisper_marker="$whisper_root/.voiceink-source-revision"
    whisper_revision="52a939a2a762224e255d366c1182b2af4dd1a032"
    whisper_sha256="6212572f00e887698440dbbf87aef27de6e56dbe73907f6148686ec55d584a19"
    whisper_archive="$HOME/Library/Caches/VoiceInkTap/whisper-$whisper_revision.tar.gz"

    mkdir -p "$(dirname "$whisper_archive")" "$whisper_parent"
    if [ ! -f "$whisper_archive" ] || ! printf '%s  %s\n' "$whisper_sha256" "$whisper_archive" | shasum -a 256 -c - >/dev/null 2>&1; then
      temporary_archive="$whisper_archive.tmp.$$"
      curl -fL --retry 3 -o "$temporary_archive" "https://github.com/ggerganov/whisper.cpp/archive/$whisper_revision.tar.gz"
      printf '%s  %s\n' "$whisper_sha256" "$temporary_archive" | shasum -a 256 -c -
      mv "$temporary_archive" "$whisper_archive"
    fi

    if [ ! -d "$whisper_framework" ] || [ ! -f "$whisper_marker" ] || [ "$(sed -n '1p' "$whisper_marker" 2>/dev/null || true)" != "$whisper_revision" ]; then
      /bin/rm -rf "$whisper_root"
      extraction_dir="$whisper_parent/.whisper-extract.$$"
      mkdir -p "$extraction_dir"
      tar -xzf "$whisper_archive" -C "$extraction_dir"
      extracted_root="$(find "$extraction_dir" -mindepth 1 -maxdepth 1 -type d -name 'whisper.cpp-*' -print -quit)"
      [ -n "$extracted_root" ] || die "Whisper source directory not found after extraction"
      mv "$extracted_root" "$whisper_root"
      /bin/rm -rf "$extraction_dir"

      cd "$whisper_root"
      grep -Fq 'echo "Building for iOS simulator..."' build-xcframework.sh || \
        die "Whisper build script layout changed; review the macOS-only build"
      awk 'index($0, "echo \"Building for iOS simulator...\"") == 1 { exit } { print }' \
        build-xcframework.sh > build-macos-only.sh
      cat >> build-macos-only.sh <<'WHISPER_SH'

    echo "Building macOS-only whisper.xcframework..."
    export DEVELOPER_DIR="${DEVELOPER_DIR:?}"
    export SDKROOT="$("/usr/bin/xcrun" --sdk macosx --show-sdk-path)"
    export CC="$("/usr/bin/xcrun" --sdk macosx --find clang)"
    export CXX="$("/usr/bin/xcrun" --sdk macosx --find clang++)"
    test -x "$CC"
    test -x "$CXX"
    test -d "$SDKROOT"
    cmake -B build-macos -G Xcode "${COMMON_CMAKE_ARGS[@]}" -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_MIN_OS_VERSION}" -DCMAKE_OSX_SYSROOT="$SDKROOT" -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_C_FLAGS="${COMMON_C_FLAGS}" -DCMAKE_CXX_FLAGS="${COMMON_CXX_FLAGS}" -DWHISPER_COREML="ON" -DWHISPER_COREML_ALLOW_FALLBACK="ON" -S .
    cmake --build build-macos --config Release -- -quiet

    setup_framework_structure "build-macos" "${MACOS_MIN_OS_VERSION}" "macos"
    combine_static_libraries "build-macos" "Release" "macos" "false"

    mkdir -p build-apple
    xcodebuild -create-xcframework -framework "$(pwd)/build-macos/framework/whisper.framework" -debug-symbols "$(pwd)/build-macos/dSYMs/whisper.dSYM" -output "$(pwd)/build-apple/whisper.xcframework"
    WHISPER_SH
      chmod 0755 build-macos-only.sh
      ./build-macos-only.sh
      printf '%s\n' "$whisper_revision" > "$whisper_marker.tmp"
      mv "$whisper_marker.tmp" "$whisper_marker"
    fi

    updater_file="$source_root/VoiceInk/App/Updates/UpdaterViewModel.swift"
    [ -f "$updater_file" ] || die "VoiceInk updater source moved; review the local-build patch"
    updater_tmp="$updater_file.local-build.tmp.$$"
    awk '
      BEGIN {
        found_import = 0
        found_class = 0
        found_view = 0
        wrapped_class = 0
      }
      $0 == "import Sparkle" {
        print "#if !LOCAL_BUILD"
        print
        print "#endif"
        found_import = 1
        next
      }
      $0 == "@MainActor" && wrapped_class == 0 {
        print "#if !LOCAL_BUILD"
        wrapped_class = 1
      }
      index($0, "final class UpdaterViewModel") == 1 {
        found_class = 1
      }
      index($0, "struct CheckForUpdatesView: View") == 1 {
        print "#else"
        print "@MainActor"
        print "final class UpdaterViewModel: NSObject, ObservableObject {"
        print "    struct AvailableUpdate: Equatable {"
        print "        let versionIdentifier: String"
        print "        let displayVersion: String"
        print "    }"
        print ""
        print "    @Published var canCheckForUpdates = false"
        print "    @Published private(set) var checksForUpdatesWhenDashboardAppears = false"
        print "    @Published private(set) var availableUpdate: AvailableUpdate?"
        print ""
        print "    override init() {"
        print "        super.init()"
        print "    }"
        print ""
        print "    func setChecksForUpdatesWhenDashboardAppears(_ value: Bool) {"
        print "        checksForUpdatesWhenDashboardAppears = value"
        print "        availableUpdate = nil"
        print "    }"
        print ""
        print "    func checkForUpdatesIfDue() {}"
        print "    func checkForUpdates() {}"
        print "}"
        print "#endif"
        print ""
        found_view = 1
      }
      {
        print
      }
      END {
        if (!found_import || !found_class || !found_view) {
          exit 42
        }
      }
    ' "$updater_file" > "$updater_tmp" || {
      /bin/rm -f "$updater_tmp"
      die "VoiceInk updater layout changed; refusing an unguarded local build"
    }
    mv "$updater_tmp" "$updater_file"

    # Xcode 26.2 ships Swift 6.2.1. The current mlx-swift package selected by
    # this VoiceInk snapshot requires Swift tools 6.3, so keep the last
    # 0.31.x package whose manifest is accepted by Xcode 26.2.
    swift_version="$(swift --version | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p')"
    [ -n "$swift_version" ] || die "Could not determine Swift toolchain version"
    case "$swift_version" in
      5.*|6.[012].*)
        resolved_file="$source_root/VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        [ -f "$resolved_file" ] || die "VoiceInk package resolution file not found"
        mlx_block="$(sed -n '/"identity" : "mlx-swift"/,/^    }/p' "$resolved_file")"
        mlx_version="$(printf '%s\n' "$mlx_block" | sed -n 's/.*"version" : "\([^"]*\)".*/\1/p')"
        case "$mlx_version" in
          0.31.4)
            ;;
          0.31.5|0.31.6)
            sed -i '' \
              -e '/"identity" : "mlx-swift"/,/^    }/ { s/"revision" : "[0-9a-f]\{40\}"/"revision" : "dc43e62d7055353c7f99fa071a4e71d29dfddc44"/; s/"version" : "[^"]*"/"version" : "0.31.4"/; }' \
              "$resolved_file"
            ;;
          *)
            die "No Xcode 26.2 compatibility pin for mlx-swift version: ${mlx_version:-unknown}"
            ;;
        esac

        syntax_block="$(sed -n '/"identity" : "swift-syntax"/,/^    }/p' "$resolved_file")"
        syntax_version="$(printf '%s\n' "$syntax_block" | sed -n 's/.*"version" : "\([^"]*\)".*/\1/p')"
        case "$syntax_version" in
          602.0.0)
            ;;
          603.0.0|603.0.1|603.0.2)
            sed -i '' \
              -e '/"identity" : "swift-syntax"/,/^    }/ { s/"revision" : "[0-9a-f]\{40\}"/"revision" : "4799286537280063c85a32f09884cfbca301b1a1"/; s/"version" : "[^"]*"/"version" : "602.0.0"/; }' \
              "$resolved_file"
            ;;
          *)
            die "No Xcode 26.2 compatibility pin for swift-syntax version: ${syntax_version:-unknown}"
            ;;
        esac
        ;;
    esac

    makefile="$source_root/Makefile"
    makefile_tmp="$makefile.xcode-package-flags.tmp.$$"
    awk '
      BEGIN { inserted = 0 }
      {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        if (!inserted && index(line, "xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release") == 1) {
          print
          print "\t\t-disableAutomaticPackageResolution \\"
          print "\t\t-onlyUsePackageVersionsFromResolvedFile \\"
          inserted = 1
          next
        }
        print
      }
      END {
        if (!inserted) {
          exit 42
        }
      }
    ' "$makefile" > "$makefile_tmp" || {
      /bin/rm -f "$makefile_tmp"
      die "VoiceInk Makefile local xcodebuild command changed; refusing an unpinned package build"
    }
    mv "$makefile_tmp" "$makefile"

    (cd "$source_root" && make local LOCAL_CODESIGN_IDENTITY=-)
    built_app="$HOME/Downloads/VoiceInk.app"
    [ -d "$built_app" ] || die "make local did not produce $built_app"
    info_plist="$built_app/Contents/Info.plist"
    [ -f "$info_plist" ] || die "VoiceInk.app has no Info.plist"
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
    [ "$bundle_id" = "com.prakashjoshipax.VoiceInk" ] || die "Unexpected VoiceInk bundle identifier: $bundle_id"

    if pgrep -x VoiceInk >/dev/null 2>&1; then
      die "VoiceInk is running; quit it before replacing the local app"
    fi

    mkdir -p "$(dirname "$target_app")"
    if [ -L "$target_app" ]; then
      die "Refusing to replace symlink: $target_app"
    fi
    if [ -e "$target_app" ] && [ ! -d "$target_app" ]; then
      die "App destination is not a directory: $target_app"
    fi

    backup_app=''
    if [ -d "$target_app" ]; then
      backup_dir="$state_root/backups/$(date -u '+%Y%m%dT%H%M%SZ')-$$"
      backup_app="$backup_dir/VoiceInk-local.app"
      mkdir -p "$backup_dir"
      ditto "$target_app" "$backup_app"
      /bin/rm -rf "$target_app"
    fi

    if ! ditto "$built_app" "$target_app"; then
      /bin/rm -rf "$target_app" || true
      if [ -n "$backup_app" ]; then
        ditto "$backup_app" "$target_app" || true
      fi
      die "Could not install $target_app"
    fi
    xattr -cr "$target_app" >/dev/null 2>&1 || true

    printf 'Installed VoiceInk source build at %s\n' "$target_app"
    if [ -n "$backup_app" ]; then
      printf 'Previous local app backup: %s\n' "$backup_app"
    fi
  SH

  installer script: {
    executable: "install-voiceink-source.sh",
    args:       [staged_path],
  }

  uninstall trash: "#{Dir.home}/Applications/VoiceInk-local.app"
end
