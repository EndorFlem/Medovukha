cask "antigravity-tools" do
  arch arm: "aarch64", intel: "x64"

  version "5.0.4"
  sha256 arm:   "f035b756d00d9eb57bfda5b281ab0851ce440b26eacf44e02846467e30207742",
         intel: "3e93d67296c78ed704a1eacaa1900530dd6af477bafee5379d85eea3ff04d5e4"

  url "https://github.com/lbjlaq/Antigravity-Manager/releases/download/v#{version}/Antigravity.Tools_#{version}_#{arch}.dmg"
  name "Antigravity Tools"
  desc "Antigravity account manager and API proxy"
  homepage "https://github.com/lbjlaq/Antigravity-Manager"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true

  app "Antigravity Tools.app"
  binary "#{appdir}/Antigravity Tools.app/Contents/MacOS/antigravity-tools"

  # Upstream ships a linker ad-hoc signature and documents this app-specific fix.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-rd", "com.apple.quarantine", "{{appdir}}/Antigravity Tools.app"],
        must_succeed: false
  end
end
