class VoiceinkSource < Formula
  desc "Free source-built local VoiceInk voice-to-text app"
  homepage "https://github.com/Beingpax/VoiceInk"
  license "GPL-3.0-only"

  # Managed by scripts/update-voiceink-formula.rb.
  VOICEINK_UPSTREAM_REVISION = "8f089cb4bf2c9c2f217b0cc0af909d9052ff6288"
  WHISPER_CPP_REVISION = "52a939a2a762224e255d366c1182b2af4dd1a032"

  url "https://github.com/Beingpax/VoiceInk/archive/#{VOICEINK_UPSTREAM_REVISION}.tar.gz"
  version "2026.09.02.184240-8f089cb4"
  sha256 "18a1322c5899fdb43566d839689ea25d31fb5ca013a1306e440b3c0781ea5e68"

  resource "whisper-cpp" do
    url "https://github.com/ggerganov/whisper.cpp/archive/#{WHISPER_CPP_REVISION}.tar.gz"
    sha256 "6212572f00e887698440dbbf87aef27de6e56dbe73907f6148686ec55d584a19"
  end

  depends_on macos: :sequoia
  depends_on arch: :arm64
  depends_on "cmake" => :build

  def disable_sparkle_for_local_build
    updater_file = buildpath / "VoiceInk/App/Updates/UpdaterViewModel.swift"
    raise "VoiceInk updater source moved; review the local-build Sparkle guard" unless updater_file.file?

    inreplace updater_file do |contents|
      import_marker = "import Sparkle\n"
      contents.sub!(import_marker, "#if !LOCAL_BUILD\n#{import_marker}#endif\n")

      class_marker = "@MainActor\nfinal class UpdaterViewModel"
      contents.sub!(class_marker, "#if !LOCAL_BUILD\n#{class_marker}")

      view_marker = "\nstruct CheckForUpdatesView: View"
      local_stub = <<~'SWIFT'
        #else
        @MainActor
        final class UpdaterViewModel: NSObject, ObservableObject {
            struct AvailableUpdate: Equatable {
                let versionIdentifier: String
                let displayVersion: String
            }

            @Published var canCheckForUpdates = false
            @Published private(set) var checksForUpdatesWhenDashboardAppears = false
            @Published private(set) var availableUpdate: AvailableUpdate?

            override init() {
                super.init()
            }

            func setChecksForUpdatesWhenDashboardAppears(_ value: Bool) {
                checksForUpdatesWhenDashboardAppears = value
                availableUpdate = nil
            }

            func checkForUpdatesIfDue() {}
            func checkForUpdates() {}
        }
        #endif

        struct CheckForUpdatesView: View
      SWIFT

      contents.sub!(view_marker, "\n#{local_stub}")
    end
  end

  def use_installed_full_xcode
    return if ENV["DEVELOPER_DIR"] && !ENV["DEVELOPER_DIR"].empty?

    full_xcode_developer_dir = Pathname("/Applications/Xcode.app/Contents/Developer")
    return unless full_xcode_developer_dir.directory?

    # xcode-select may point at the CLT shim even when the full Xcode bundle
    # is installed. Prefer that bundle for the formula build unless the user
    # explicitly selected another developer directory.
    ENV["DEVELOPER_DIR"] = full_xcode_developer_dir.to_s
  end

  def build_macos_only_whisper(whisper_framework)
    resource("whisper-cpp").stage do
      upstream_script = Pathname("build-xcframework.sh").read
      platform_marker = "echo \"Building for iOS simulator...\""
      raise "whisper build script layout changed; review the macOS-only extraction" unless upstream_script.include?(platform_marker)

      common_functions = upstream_script.split(platform_marker, 2).first
      macos_script = <<~SH
        #{common_functions}

        echo "Building macOS-only whisper.xcframework..."
        cmake -B build-macos -G Xcode "__DOLLAR__{COMMON_CMAKE_ARGS[@]}" -DCMAKE_OSX_DEPLOYMENT_TARGET=__DOLLAR__{MACOS_MIN_OS_VERSION} -DCMAKE_OSX_SYSROOT="__DOLLAR__(xcrun --sdk macosx --show-sdk-path)" -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_C_FLAGS="__DOLLAR__{COMMON_C_FLAGS}" -DCMAKE_CXX_FLAGS="__DOLLAR__{COMMON_CXX_FLAGS}" -DWHISPER_COREML="ON" -DWHISPER_COREML_ALLOW_FALLBACK="ON" -S .
        cmake --build build-macos --config Release -- -quiet

        setup_framework_structure "build-macos" __DOLLAR__{MACOS_MIN_OS_VERSION} "macos"
        combine_static_libraries "build-macos" "Release" "macos" "false"

        mkdir -p build-apple
        xcodebuild -create-xcframework -framework "$(pwd)/build-macos/framework/whisper.framework" -debug-symbols "$(pwd)/build-macos/dSYMs/whisper.dSYM" -output "$(pwd)/build-apple/whisper.xcframework"
      SH
      macos_script = macos_script.gsub("__DOLLAR__", "$")

      macos_script_path = Pathname("build-macos-only.sh")
      macos_script_path.write(macos_script)
      chmod 0755, macos_script_path
      system "./build-macos-only.sh"

      whisper_framework.dirname.mkpath
      cp_r "build-apple/whisper.xcframework", whisper_framework.dirname
    end
  end

  def install
    disable_sparkle_for_local_build

    # The upstream Makefile uses HOME for both the Whisper dependency and its
    # Downloads build output. Point it at the formula build directory so an
    # install does not write into the user's home directory.
    original_home = ENV["HOME"]
    original_developer_dir = ENV["DEVELOPER_DIR"]
    begin
      use_installed_full_xcode
      ENV["HOME"] = buildpath.to_s

      whisper_framework = buildpath / "VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework"
      build_macos_only_whisper(whisper_framework)

      system "make", "local", "LOCAL_CODESIGN_IDENTITY=-"
    ensure
      ENV["HOME"] = original_home
      ENV["DEVELOPER_DIR"] = original_developer_dir
    end

    built_app = buildpath / "Downloads/VoiceInk.app"
    raise "make local did not produce #{built_app}" unless built_app.directory?
    raise "VoiceInk.app is missing its Info.plist" unless (built_app / "Contents/Info.plist").file?

    bundle_id = Utils.safe_popen_read(
      "/usr/libexec/PlistBuddy",
      "-c",
      "Print :CFBundleIdentifier",
      (built_app / "Contents/Info.plist").to_s,
    ).strip
    raise "unexpected VoiceInk bundle identifier: #{bundle_id}" unless bundle_id == "com.prakashjoshipax.VoiceInk"

    libexec.install built_app

    launcher = bin / "voiceink-source"
    launcher.write <<~SH
      #!/bin/bash
      set -euo pipefail

      app_path="#{opt_prefix}/libexec/VoiceInk.app"
      case "${1:-}" in
        --path)
          printf '%s\\n' "$app_path"
          ;;
        --version)
          /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist"
          ;;
        *)
          exec /usr/bin/open "$app_path" --args "$@"
          ;;
      esac
    SH
    chmod 0755, launcher
  end

  test do
    app = libexec / "VoiceInk.app"
    info_plist = app / "Contents/Info.plist"

    assert_predicate app, :directory?
    assert_predicate info_plist, :file?
    assert_equal "com.prakashjoshipax.VoiceInk",
      shell_output("/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' '#{info_plist}'").strip
    assert_match(/\A\d+(?:\.\d+)+\z/, shell_output("#{bin}/voiceink-source --version").strip)
    assert_equal "#{opt_prefix}/libexec/VoiceInk.app", shell_output("#{bin}/voiceink-source --path").strip
  end
end
