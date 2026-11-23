#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rubygems/version"

CASK_PATH = File.expand_path("../Casks/antigravity-unlocker.rb", __dir__)

output, error, status = Open3.capture3("gh", "api", "repos/confeden/Antigravity/releases/latest")
abort "Could not fetch the Antigravity Unlocker release: #{error.strip}" unless status.success?
release = JSON.parse(output)
tag = release.fetch("tag_name")
match = /\Av(\d+(?:\.\d+){1,3})\z/.match(tag)
abort "Unexpected stable release: #{tag}" unless match && !release.fetch("prerelease") && !release.fetch("draft")
version = match[1]

asset_name = "AG_#{version}_macos.tar.gz"
asset = release.fetch("assets").find { |entry| entry["name"] == asset_name }
abort "Release #{tag} has no #{asset_name}; review the macOS archive naming" unless asset
expected_url = "https://github.com/confeden/Antigravity/releases/download/#{tag}/#{asset_name}"
abort "Unexpected macOS download URL" unless asset.fetch("browser_download_url") == expected_url
digest = /\Asha256:([0-9a-f]{64})\z/.match(asset.fetch("digest", "").to_s)
abort "GitHub did not provide a SHA256 digest; review the release manually" unless digest
sha256 = digest[1]

cask = File.read(CASK_PATH)
current = cask[/^  version "([^"]+)"$/, 1]
current_sha256 = cask[/^  sha256 "([0-9a-f]{64})"$/, 1]
abort "Cask version or checksum marker is missing" unless current && current_sha256
abort "Refusing to downgrade #{current} to #{version}" if Gem::Version.new(version) < Gem::Version.new(current)
if version == current
  abort "The release checksum changed without a version bump; review it manually" unless sha256 == current_sha256
  puts "Antigravity Unlocker cask is already at #{tag}."
  exit 0
end

updated = cask.sub(/^  version "[^"]+"$/, "  version \"#{version}\"")
updated = updated.sub(/^  sha256 "[0-9a-f]{64}"$/, "  sha256 \"#{sha256}\"")
temporary_path = "#{CASK_PATH}.tmp.#{$$}"
begin
  File.write(temporary_path, updated)
  File.rename(temporary_path, CASK_PATH)
ensure
  File.delete(temporary_path) if File.file?(temporary_path)
end
puts "Updated Antigravity Unlocker cask to #{tag} (SHA256 #{sha256})."
