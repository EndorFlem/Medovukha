cask "monocode" do
  version "0.12.0"
  sha256 "51566d32d93bdb571d49aa937ade8900b377db487ed69f015da5a4fa72f5b28c"

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
