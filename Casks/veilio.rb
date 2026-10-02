cask "veilio" do
  version "0.2.0"
  sha256 "0e63fcc2bab0ba4171e34567b594c491c681fa475d59c2d424edbb8507d9e187"

  url "https://lupus-storage.sgp1.cdn.digitaloceanspaces.com/veilio/releases/Veilio_#{version}_aarch64.dmg"
  name "Veilio"
  desc "Privacy-first desktop AI assistant for meetings and screen shares"
  homepage "https://www.veilio.works/"

  livecheck do
    skip "Version is managed by the official Veilio website updater."
  end

  depends_on arch: :arm64
  depends_on :macos

  app "Veilio.app"
end
