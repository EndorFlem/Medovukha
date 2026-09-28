cask "monocode" do
  version "0.3.0"
  sha256 "706b4ed03a546c121064d56c260a05eb3c18a2594252cb94f1293f843fccded8"

  url "https://github.com/hardbeat920/monocode/releases/download/v#{version}/MonoCode_#{version}_aarch64.dmg"
  name "MonoCode"
  desc "Desktop GUI for coding agents"
  homepage "https://github.com/hardbeat920/monocode"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64

  app "MonoCode.app"
end
