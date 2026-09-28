#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"

UPSTREAM_REPOSITORY = "hardbeat920/monocode"
CASK_PATH = File.expand_path("../Casks/monocode.rb", __dir__)

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

headers = {
  "Accept" => "application/vnd.github+json",
  "User-Agent" => "medovukha-monocode-updater",
}
token = ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"]
headers["Authorization"] = "Bearer #{token}" unless token.nil? || token.empty?

release = JSON.parse(http_get(
  "https://api.github.com/repos/#{UPSTREAM_REPOSITORY}/releases/latest",
  headers,
))
release_tag = release["tag_name"].to_s
fail_with("latest release has no v-prefixed semantic version tag") unless release_tag.match?(/\Av\d+\.\d+\.\d+\z/)

version = release_tag.delete_prefix("v")
asset_name = "MonoCode_#{version}_aarch64.dmg"
asset = Array(release["assets"]).find { |candidate| candidate["name"] == asset_name }
fail_with("release #{release_tag} has no #{asset_name} asset") if asset.nil?

archive_sha256 = Digest::SHA256.hexdigest(http_get(
  asset["browser_download_url"],
  { "User-Agent" => "medovukha-monocode-updater" },
))

cask = File.read(CASK_PATH)
current_version = cask[/^\s*version\s+"([^"]+)"/, 1]
current_sha256 = cask[/^\s*sha256\s+"([0-9a-f]{64})"/, 1]
fail_with("cask has no version or sha256") if current_version.nil? || current_sha256.nil?

if current_version == version && current_sha256 == archive_sha256
  puts "MonoCode cask is already at #{release_tag}."
  exit 0
end

updated = cask.dup
updated.sub!(/(^\s*version\s+")[^"]+(")/) do
  "#{Regexp.last_match(1)}#{version}#{Regexp.last_match(2)}"
end
updated.sub!(/(^\s*sha256\s+")[0-9a-f]{64}(")/) do
  "#{Regexp.last_match(1)}#{archive_sha256}#{Regexp.last_match(2)}"
end
fail_with("cask update markers were incomplete") if updated == cask

temporary_path = "#{CASK_PATH}.tmp.#{$$}"
begin
  File.write(temporary_path, updated)
  File.rename(temporary_path, CASK_PATH)
ensure
  File.delete(temporary_path) if File.file?(temporary_path)
end

puts "Updated MonoCode cask."
puts "  release: #{release_tag}"
puts "  sha256:  #{archive_sha256}"
