cask "hiddify" do
  version "5.9.15"
  sha256 "5d095a63af1130535f3f2dc50342242df2c2ea5bc153151c8ef79923cc6cbd3f"

  url "https://github.com/hiddify/hiddify-app/releases/download/v#{version}/Hiddify-MacOS.dmg"
  name "Hiddify"
  desc "Multi-platform proxy client based on Sing-box"
  homepage "https://github.com/hiddify/hiddify-app"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :monterey

  app "Hiddify.app"
end
