cask "hiddify" do
  version "5.5.5"
  sha256 "3e8c1d1448f861e5594910e168f11dc39e52ecfb68c03d445f9fb1721032992e"

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
