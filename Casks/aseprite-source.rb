cask "aseprite-source" do
  version "1.3.18.6,1"
  sha256 "fa9dd07a0c2a5ec91a4166333296bbb9e5c237933b59875d0cfee849d2358306"

  url "https://github.com/aseprite/aseprite/releases/download/v#{version.csv.first}/Aseprite-v#{version.csv.first}-Source.zip"
  name "Aseprite source build"
  desc "Locally built pixel art and animation editor"
  homepage "https://github.com/aseprite/aseprite"

  livecheck do
    skip "Version is maintained by the Aseprite source release updater."
  end

  depends_on arch: :arm64
  depends_on macos: :sequoia
  depends_on formula: ["cmake", "ninja"]

  generated_script "install-aseprite-source.sh", content: <<~'SH'
    #!/bin/bash
    set -euo pipefail

    die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
    user_home="${HOME:?HOME is required}"
    source_root="${1:?Missing staged source directory}"
    target_app="$user_home/Applications/Aseprite.app"
    state_root="$user_home/Library/Application Support/Medovukha/Aseprite"
    skia_url="https://github.com/aseprite/skia/releases/download/m124-08a5439a6b/Skia-macOS-Release-arm64.zip"
    skia_sha="22663000967fc2c3f1a78190082228474955de02ffd13a352b39a48b204dac9a"
    strings_revision="0a3cef0b825be6b4e18dff331386380181b1d743"
    strings_sha="dfb63c3bfd79fcade99b256660d6bf78aeed1e1984bd3bed8d61adc0e5f47911"

    [ -f "$source_root/CMakeLists.txt" ] || die "The source archive has an unexpected layout"
    [ -f "$source_root/laf/CMakeLists.txt" ] || die "The source archive is missing its submodules"
    for cmd in cmake ninja curl unzip tar shasum ditto codesign sips iconutil xcodebuild xcrun; do
      command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
    done
    if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
      export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
    xcodebuild -version >/dev/null 2>&1 || die "Full Xcode is required; set DEVELOPER_DIR to its Developer directory"
    sdk="$(xcrun --sdk macosx --show-sdk-path)" || die "macOS SDK not found"
    [ -d "$sdk" ] || die "macOS SDK directory not found: $sdk"

    validate_target() {
      if [ -e /Applications/Aseprite.app ] || [ -L /Applications/Aseprite.app ]; then
        die "Another Aseprite.app exists in /Applications; resolve the conflict before installing"
      fi
      if pgrep -f "$target_app/Contents/MacOS/aseprite" >/dev/null; then
        die "Quit Aseprite before upgrading"
      fi
      [ ! -L "$target_app" ] || die "Refusing to replace a symlink: $target_app"
      if [ -e "$target_app" ]; then
        [ -d "$target_app" ] || die "The destination is not an app directory: $target_app"
        bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist" 2>/dev/null || true)"
        [ "$bundle_id" = org.aseprite.Aseprite ] || die "Refusing to replace an unrelated app: $target_app"
        [ "$(cat "$target_app/Contents/Resources/.medovukha-aseprite-source" 2>/dev/null || true)" = medovukha-aseprite-source ] || \
          die "Refusing to replace an Aseprite app not installed by this cask: $target_app"
      fi
    }
    validate_target

    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/medovukha-aseprite.XXXXXXXX")"
    stage_dir=''
    backup=''
    cleanup() {
      if [ -n "$backup" ] && [ -d "$backup" ] && [ ! -e "$target_app" ]; then
        mv "$backup" "$target_app" || printf 'Could not restore previous app from %s\n' "$backup" >&2
      fi
      [ -z "$stage_dir" ] || /bin/rm -rf "$stage_dir"
      /bin/rm -rf "$work_dir"
    }
    trap cleanup EXIT

    curl -fL --retry 3 -o "$work_dir/skia.zip" "$skia_url"
    printf '%s  %s\n' "$skia_sha" "$work_dir/skia.zip" | shasum -a 256 -c - >/dev/null || die "Skia checksum mismatch"
    mkdir "$work_dir/skia"
    unzip -q "$work_dir/skia.zip" -d "$work_dir/skia"
    skia_lib="$work_dir/skia/out/Release-arm64/libskia.a"
    [ -f "$skia_lib" ] || die "Skia archive has an unexpected layout"

    curl -fL --retry 3 -o "$work_dir/strings.tar.gz" "https://codeload.github.com/aseprite/strings/tar.gz/$strings_revision"
    printf '%s  %s\n' "$strings_sha" "$work_dir/strings.tar.gz" | shasum -a 256 -c - >/dev/null || die "Translation archive checksum mismatch"

    cmake -S "$source_root" -B "$work_dir/build" -G Ninja \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
      -DCMAKE_OSX_SYSROOT="$sdk" \
      -DLAF_BACKEND=skia \
      -DSKIA_DIR="$work_dir/skia" \
      -DSKIA_LIBRARY_DIR="$work_dir/skia/out/Release-arm64" \
      -DSKIA_LIBRARY="$skia_lib" \
      -DPNG_ARM_NEON:STRING=on \
      -DENABLE_I18N_STRINGS=OFF \
      -DENABLE_UPDATER=OFF \
      -DENABLE_TESTS=OFF
    cmake --build "$work_dir/build" --target aseprite --parallel 4

    built_app="$work_dir/build/bin/Aseprite.app"
    [ -x "$built_app/Contents/MacOS/aseprite" ] || die "The build did not produce Aseprite.app"
    resources="$built_app/Contents/Resources"
    mkdir -p "$resources/data/strings.git"
    tar -xzf "$work_dir/strings.tar.gz" --strip-components=1 -C "$resources/data/strings.git"
    cp "$source_root/data/strings/en.ini" "$resources/data/strings.git/en.ini"

    for icon in Aseprite:ase Document:doc Extension:ext; do
      icon_name="${icon%%:*}"
      icon_prefix="${icon#*:}"
      png="$source_root/data/icons/${icon_prefix}256.png"
      [ -f "$png" ] || die "Missing icon: $png"
      iconset="$work_dir/${icon_name}.iconset"
      mkdir "$iconset"
      for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
      done
      iconutil -c icns "$iconset" -o "$resources/${icon_name}.icns"
    done

    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built_app/Contents/Info.plist")"
    [ "$bundle_id" = org.aseprite.Aseprite ] || die "Unexpected upstream bundle identifier: $bundle_id"
    printf 'medovukha-aseprite-source\n' > "$resources/.medovukha-aseprite-source"
    codesign --force --deep --sign - "$built_app"
    codesign --verify --deep --strict "$built_app"
    validate_target
    mkdir -p "$user_home/Applications" "$state_root/backups"

    stage_dir="$(mktemp -d "$user_home/Applications/.aseprite-stage.XXXXXXXX")"
    ditto "$built_app" "$stage_dir/Aseprite.app"
    xattr -cr "$stage_dir/Aseprite.app" >/dev/null 2>&1 || true
    if [ -d "$target_app" ]; then
      backup_dir="$(mktemp -d "$state_root/backups/aseprite.XXXXXXXX")"
      backup="$backup_dir/Aseprite.app"
      mv "$target_app" "$backup"
    fi
    if ! mv "$stage_dir/Aseprite.app" "$target_app"; then
      [ -z "$backup" ] || mv "$backup" "$target_app" || true
      die "Could not install $target_app"
    fi
    printf 'Installed %s\n' "$target_app"
    [ -z "$backup" ] || printf 'Previous app backup: %s\n' "$backup"
  SH

  installer script: {
    executable: "install-aseprite-source.sh",
    args:       [staged_path],
  }

  generated_script "check-aseprite-uninstall.sh", content: <<~'SH'
    #!/bin/bash
    set -eu
    target_app="${HOME:?HOME is required}/Applications/Aseprite.app"
    if [ ! -e "$target_app" ] && [ ! -L "$target_app" ]; then
      exit 0
    fi
    [ ! -L "$target_app" ] || { printf 'Refusing to remove symlink: %s\n' "$target_app" >&2; exit 1; }
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist" 2>/dev/null || true)"
    marker="$(cat "$target_app/Contents/Resources/.medovukha-aseprite-source" 2>/dev/null || true)"
    if [ "$bundle_id" != org.aseprite.Aseprite ] || [ "$marker" != medovukha-aseprite-source ]; then
      printf 'Refusing to remove an app not installed by this cask: %s\n' "$target_app" >&2
      exit 1
    fi
  SH

  uninstall script: {
              executable:   "check-aseprite-uninstall.sh",
              must_succeed: true,
            },
            trash:  "#{Dir.home}/Applications/Aseprite.app"

  caveats <<~EOS
    Builds Aseprite locally for Apple Silicon. Full Xcode and the macOS SDK are required.
    The source license permits personal builds; see https://github.com/aseprite/aseprite/blob/main/EULA.txt.
    The app is installed as ~/Applications/Aseprite.app.
  EOS
end
