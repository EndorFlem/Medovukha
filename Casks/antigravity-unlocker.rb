cask "antigravity-unlocker" do
  version "2.34.0"
  sha256 "ee5d60236b9230aca719b454ffba4f5425eb8f47af9a883037b9975040723e33"

  url "https://github.com/confeden/Antigravity/releases/download/v#{version}/AG_#{version}_macos.tar.gz"
  name "Antigravity Unlocker"
  desc "Antigravity regional access patcher and local routing helper"
  homepage "https://github.com/confeden/Antigravity"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  suite "AG_#{version}_macos", target: "Antigravity Unlocker"

  command_wrapper "antigravity-unlocker", content: <<~SH
    #!/bin/sh
    cd "#{appdir}/Antigravity Unlocker" || exit 1
    exec ./ag_unlocker "$@"
  SH

  # Match the app-specific quarantine removal in the vendor's .command launcher.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-rd", "com.apple.quarantine", "{{appdir}}/Antigravity Unlocker"],
        must_succeed: false
  end

  caveats <<~EOS
    Run antigravity-unlocker for the graphical interface, or antigravity-unlocker --tui.
    The vendor requires a free activation key from its Telegram group; see the homepage.
    Before uninstalling, disable the unlocker's features in its interface to restore
    patched files and remove its background services.
  EOS
end
