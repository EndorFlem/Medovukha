#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "rubygems/version"
require "uri"

HOMEPAGE = "https://www.veilio.works/"
CASK_PATH = File.expand_path("../Casks/veilio.rb", __dir__)
ASSET_HOST = "lupus-storage.sgp1.cdn.digitaloceanspaces.com"
ASSET_PATTERN = %r{\A/veilio/releases/Veilio_(\d+\.\d+\.\d+)_aarch64\.dmg\z}

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
  "Accept" => "text/html,application/xhtml+xml",
  "User-Agent" => "medovukha-veilio-updater",
}
homepage = http_get(HOMEPAGE, headers)

candidates = homepage.scan(%r{https://#{Regexp.escape(ASSET_HOST)}([^"'<>[:space:]]+)}).map do |match|
  path = match.first
  version = path[ASSET_PATTERN, 1]
  next if version.nil?

  [Gem::Version.new(version), version, "https://#{ASSET_HOST}#{path}"]
end.compact.uniq
fail_with("could not find an official Apple Silicon Veilio DMG on #{HOMEPAGE}") if candidates.empty?

_sort_version, version, download_url = candidates.max_by(&:first)
download_uri = URI(download_url)
fail_with("unexpected Veilio download host: #{download_uri.host}") unless download_uri.host == ASSET_HOST
fail_with("unexpected Veilio download path: #{download_uri.path}") unless download_uri.path.match?(ASSET_PATTERN)

archive = http_get(download_url, { "User-Agent" => "medovukha-veilio-updater" })
archive_sha256 = Digest::SHA256.hexdigest(archive)

cask = File.read(CASK_PATH)
current_version = cask[/^\s*version\s+"([^"]+)"/, 1]
current_sha256 = cask[/^\s*sha256\s+"([0-9a-f]{64})"/, 1]
fail_with("cask has no version or sha256") if current_version.nil? || current_sha256.nil?

if current_version == version && current_sha256 == archive_sha256
  puts "Veilio cask is already at #{version}."
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

puts "Updated Veilio cask."
puts "  version: #{version}"
puts "  sha256:  #{archive_sha256}"
