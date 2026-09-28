#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "open3"
require "time"
require "tmpdir"
require "uri"

UPSTREAM_REPOSITORY = "hardbeat920/monocode"
CASK_PATH = File.expand_path("../Casks/monocode-source.rb", __dir__)
PATCH_PATH = File.expand_path("../patches/monocode-omp-rpc-v2.patch", __dir__)

def fail_with(message)
  warn "Error: #{message}"
  exit 1
end

def http_get(url, headers = {}, redirects_left = 5)
  fail_with("too many HTTP redirects while fetching #{url}") if redirects_left.zero?

  uri = URI(url)
  request = Net::HTTP::Get.new(uri)
  headers.each { |key, value| request[key] = value }

  response = Net::HTTP.start(
    uri.host,
    uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: 20,
    read_timeout: 180,
  ) { |http| http.request(request) }

  case response
  when Net::HTTPSuccess
    response.body
  when Net::HTTPRedirection
    location = response["location"]
    fail_with("redirect from #{url} has no location") if location.nil? || location.empty?

    http_get(URI.join(url, location).to_s, headers, redirects_left - 1)
  else
    fail_with("HTTP #{response.code} while fetching #{url}")
  end
rescue SocketError, SystemCallError, Timeout::Error => e
  fail_with("network error while fetching #{url}: #{e.message}")
end

def check_patch_applies(archive, patch)
  Dir.mktmpdir("monocode-source-update") do |directory|
    archive_path = File.join(directory, "source.tar.gz")
    File.binwrite(archive_path, archive)
    _stdout, stderr, status = Open3.capture3("tar", "-xzf", archive_path, "-C", directory)
    fail_with("could not extract the upstream archive: #{stderr}") unless status.success?

    source_root = Dir.children(directory)
      .map { |entry| File.join(directory, entry) }
      .find { |entry| File.directory?(entry) && File.file?(File.join(entry, "package.json")) }
    fail_with("upstream archive has no MonoCode package root") if source_root.nil?

    _stdout, stderr, status = Open3.capture3(
      "patch",
      "-p1",
      "--batch",
      "--forward",
      "--dry-run",
      "-d",
      source_root,
      stdin_data: patch,
    )
    fail_with("OMP RPC patch no longer applies to upstream main:\n#{stderr}") unless status.success?
  end
end

headers = {
  "Accept" => "application/vnd.github+json",
  "User-Agent" => "medovukha-monocode-source-updater",
}
token = ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"]
headers["Authorization"] = "Bearer #{token}" unless token.nil? || token.empty?

commit = JSON.parse(http_get(
  "https://api.github.com/repos/#{UPSTREAM_REPOSITORY}/commits/main",
  headers,
))
revision = commit["sha"].to_s
fail_with("main commit response has no SHA") unless revision.match?(/\A[0-9a-f]{40}\z/)

commit_date = commit.dig("commit", "author", "date").to_s
timestamp = Time.iso8601(commit_date).utc.strftime("%Y.%m.%d.%H%M%S")
version = "#{timestamp}-#{revision[0, 7]}"
archive = http_get(
  "https://github.com/#{UPSTREAM_REPOSITORY}/archive/#{revision}.tar.gz",
  { "User-Agent" => "medovukha-monocode-source-updater" },
)
patch = File.binread(PATCH_PATH)
check_patch_applies(archive, patch)

archive_sha256 = Digest::SHA256.hexdigest(archive)
cask = File.read(CASK_PATH)
current_revision = cask[/^\s*monocode_upstream_revision\s*=\s*"([0-9a-f]{40})"/, 1]
current_version = cask[/^\s*version\s+"([^"]+)"/, 1]
current_sha256 = cask[/^\s*sha256\s+"([0-9a-f]{64})"/, 1]
fail_with("cask has no version, source revision, or sha256") if [current_version, current_revision, current_sha256].any?(&:nil?)

if current_revision == revision && current_version == version && current_sha256 == archive_sha256
  puts "MonoCode source cask is already at #{revision[0, 7]}."
  exit 0
end

updated = cask.dup
updated.sub!(/(^\s*version\s+")[^"]+(")/) do
  "#{Regexp.last_match(1)}#{version}#{Regexp.last_match(2)}"
end
updated.sub!(/(^\s*sha256\s+")[0-9a-f]{64}(")/) do
  "#{Regexp.last_match(1)}#{archive_sha256}#{Regexp.last_match(2)}"
end
updated.sub!(/(^\s*monocode_upstream_revision\s*=\s*")[0-9a-f]{40}(")/) do
  "#{Regexp.last_match(1)}#{revision}#{Regexp.last_match(2)}"
end
fail_with("cask update markers were incomplete") if updated == cask

temporary_path = "#{CASK_PATH}.tmp.#{$$}"
begin
  File.write(temporary_path, updated)
  File.rename(temporary_path, CASK_PATH)
ensure
  File.delete(temporary_path) if File.file?(temporary_path)
end

puts "Updated MonoCode source cask."
puts "  revision: #{revision}"
puts "  version:  #{version}"
puts "  sha256:   #{archive_sha256}"
