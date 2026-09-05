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

  def install
    disable_sparkle_for_local_build

    # The upstream Makefile uses HOME for both the Whisper dependency and its
    # Downloads build output. Point it at the formula build directory so an
    # install does not write into the user's home directory.
    original_home = ENV["HOME"]
    begin
      ENV["HOME"] = buildpath.to_s

      whisper_framework = buildpath / "VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework"
      resource("whisper-cpp").stage do
        system "./build-xcframework.sh"
        whisper_framework.dirname.mkpath
        cp_r "build-apple/whisper.xcframework", whisper_framework.dirname
      end

      system "make", "local", "LOCAL_CODESIGN_IDENTITY=-"
    ensure
      ENV["HOME"] = original_home
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
