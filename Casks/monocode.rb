cask "monocode" do
  version "0.15.0"
  sha256 "c3d54759650071fc1a5f3a5b7af5c4a52121a703253f090f8e01f89ecb677ef1"

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
