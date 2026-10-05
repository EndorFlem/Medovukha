cask "monocode" do
  version "0.7.0"
  sha256 "e1a46b279ce06e29135b24c413c4e02864f09091c5533e66f8f1cb93b63ad00e"

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
