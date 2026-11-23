#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rubygems/version"
require "tempfile"

ROOT = File.expand_path("..", __dir__)
PATCHER_REPOSITORY = "trustybird/AvenCores-open-antigravity-patcher"
MANAGER_REPOSITORY = "lbjlaq/Antigravity-Manager"

def capture!(*command)
  output, error, status = Open3.capture3(*command)
  abort "#{command.first} failed: #{error.strip}" unless status.success?
  output
end

def latest_release(repository)
  release = JSON.parse(capture!("gh", "api", "repos/#{repository}/releases/latest"))
  tag = release.fetch("tag_name")
  match = /\Av?(\d+(?:\.\d+){1,3})\z/.match(tag)
  abort "Unexpected stable release for #{repository}: #{tag}" unless match && !release.fetch("prerelease") && !release.fetch("draft")
  [release, match[1]]
end

def current_version(contents)
  contents[/^  version "([^"]+)"$/, 1] || abort("Version marker is missing")
end

def check_version(current, latest)
  abort "Refusing to downgrade #{current} to #{latest}" if Gem::Version.new(latest) < Gem::Version.new(current)
end

def replace!(contents, pattern, replacement)
  abort "Update marker is missing: #{pattern}" unless contents.match?(pattern)
  contents.sub(pattern, replacement)
end

def write_update(path, contents)
  temporary_path = "#{path}.tmp.#{$$}"
  begin
    File.write(temporary_path, contents)
    File.rename(temporary_path, path)
  ensure
    File.delete(temporary_path) if File.file?(temporary_path)
  end
end

patcher_path = File.join(ROOT, "Formula/open-ag-patcher.rb")
patcher = File.read(patcher_path)
release, version = latest_release(PATCHER_REPOSITORY)
current = current_version(patcher)
check_version(current, version)
if version == current
  puts "Open AG Patcher is already at #{version}."
else
  tag = release.fetch("tag_name")
  revision = JSON.parse(capture!("gh", "api", "repos/#{PATCHER_REPOSITORY}/commits/#{tag}")).fetch("sha")
  abort "Invalid patcher revision" unless revision.match?(/\A[0-9a-f]{40}\z/)
  url = "https://github.com/#{PATCHER_REPOSITORY}/archive/#{revision}.tar.gz"
  Tempfile.create(["open-ag-patcher-", ".tar.gz"]) do |file|
    capture!("curl", "-fsSL", "--retry", "3", "--connect-timeout", "20", "--max-time", "180", "-o", file.path, url)
    source_root = "AvenCores-open-antigravity-patcher-#{revision}/source"
    requirements = capture!("tar", "-xOzf", file.path, "#{source_root}/requirements.txt").lines.map(&:strip).reject(&:empty?).sort
    abort "Patcher dependencies changed; review the formula manually" unless requirements == %w[packaging pyinstaller]
    constants = capture!("tar", "-xOzf", file.path, "#{source_root}/patcher/constants.py")
    abort "Patcher source version does not match its release" unless constants.include?("VERSION = \"#{version}\"")
    updated = replace!(patcher, /^  version "[^"]+"$/, "  version \"#{version}\"")
    updated = replace!(updated, /^  patcher_upstream_revision = "[0-9a-f]{40}"$/, "  patcher_upstream_revision = \"#{revision}\"")
    updated = replace!(updated, /^  sha256 "[0-9a-f]{64}"$/, "  sha256 \"#{Digest::SHA256.file(file.path).hexdigest}\"")
    write_update(patcher_path, updated)
  end
  puts "Updated Open AG Patcher to #{version}."
end

manager_path = File.join(ROOT, "Casks/antigravity-tools.rb")
manager = File.read(manager_path)
release, version = latest_release(MANAGER_REPOSITORY)
check_version(current_version(manager), version)
tag = release.fetch("tag_name")
abort "Unexpected Antigravity Tools release tag: #{tag}" unless tag == "v#{version}"
checksums = %w[aarch64 x64].map do |arch|
  name = "Antigravity.Tools_#{version}_#{arch}.dmg"
  asset = release.fetch("assets").find { |entry| entry["name"] == name }
  abort "Release #{tag} has no #{name}" unless asset
  url = "https://github.com/#{MANAGER_REPOSITORY}/releases/download/#{tag}/#{name}"
  abort "Unexpected download URL for #{name}" unless asset.fetch("browser_download_url") == url
  digest = /\Asha256:([0-9a-f]{64})\z/.match(asset.fetch("digest", "").to_s)
  abort "Missing GitHub SHA256 digest for #{name}; review the release manually" unless digest
  digest[1]
end
updated = replace!(manager, /^  version "[^"]+"$/, "  version \"#{version}\"")
updated = replace!(updated, /^  sha256 arm:   "[0-9a-f]{64}",$/, "  sha256 arm:   \"#{checksums[0]}\",")
updated = replace!(updated, /^         intel: "[0-9a-f]{64}"$/, "         intel: \"#{checksums[1]}\"")
if updated == manager
  puts "Antigravity Tools is already at #{version}."
else
  abort "Release checksum changed without a version bump; review it manually" if current_version(manager) == version
  write_update(manager_path, updated)
  puts "Updated Antigravity Tools to #{version}."
end
