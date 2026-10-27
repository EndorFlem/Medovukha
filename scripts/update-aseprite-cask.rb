#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rubygems/version"
require "tempfile"

CASK_PATH = File.expand_path("../Casks/aseprite-source.rb", __dir__)

def capture!(*command)
  output, error, status = Open3.capture3(*command)
  abort "#{command.first} failed: #{error.strip}" unless status.success?
  output
end

release = JSON.parse(capture!("gh", "api", "repos/aseprite/aseprite/releases/latest"))
tag = release.fetch("tag_name")
match = /\Av(\d+(?:\.\d+){1,3})\z/.match(tag)
abort "Unexpected stable release tag: #{tag}" unless match && !release.fetch("prerelease")
version = match[1]
cask = File.read(CASK_PATH)
current = cask[/^  version "([^"]+)"$/, 1]
abort "Cask version marker is missing" unless current
current_upstream = current.split(",", 2).first
abort "Refusing to downgrade #{current_upstream} to #{version}" if Gem::Version.new(version) < Gem::Version.new(current_upstream)
if version == current_upstream
  puts "Aseprite source cask is already at #{tag}."
  exit 0
end

asset_name = "Aseprite-#{tag}-Source.zip"
asset = release.fetch("assets").find { |entry| entry["name"] == asset_name }
abort "Release #{tag} has no official source archive" unless asset
url = asset.fetch("browser_download_url")
expected_url = "https://github.com/aseprite/aseprite/releases/download/#{tag}/#{asset_name}"
abort "Unexpected source archive URL" unless url == expected_url

Tempfile.create(["aseprite-source-", ".zip"]) do |file|
  capture!("curl", "-fsSL", "--retry", "3", "--max-time", "900", "-o", file.path, url)
  sha256 = Digest::SHA256.file(file.path).hexdigest
  digest = asset["digest"]
  abort "Release asset digest mismatch" if digest && digest != "sha256:#{sha256}"

  instructions = capture!("unzip", "-p", file.path, "INSTALL.md")
  build_config = capture!("unzip", "-p", file.path, "src/CMakeLists.txt")
  manifest = capture!("unzip", "-Z", "-1", file.path)
  abort "Review the Skia dependency before updating; m124 is no longer specified" unless instructions.include?("aseprite-m124")
  abort "Review changed macOS bundle layout before updating" unless build_config.include?("bin/Aseprite.app/Contents/MacOS/aseprite")
  abort "Source archive is missing the laf submodule" unless manifest.lines.map(&:strip).include?("laf/CMakeLists.txt")

  updated = cask.sub(/^  version "[^"]+"$/, "  version \"#{version},1\"")
  updated = updated.sub(/^  sha256 "[0-9a-f]{64}"$/, "  sha256 \"#{sha256}\"")
  abort "Cask update markers were incomplete" if updated == cask || !updated.include?("  sha256 \"#{sha256}\"")

  temporary_path = "#{CASK_PATH}.tmp.#{$$}"
  begin
    File.write(temporary_path, updated)
    File.rename(temporary_path, CASK_PATH)
  ensure
    File.delete(temporary_path) if File.file?(temporary_path)
  end
  puts "Updated Aseprite source cask to #{tag} (SHA256 #{sha256})."
end
