#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "open3"
require "time"
require "uri"

UPSTREAM_REPOSITORY = "Beingpax/VoiceInk"
UPSTREAM_URL = "https://github.com/#{UPSTREAM_REPOSITORY}.git"
CASK_PATH = File.expand_path("../Casks/voiceink-source.rb", __dir__)

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
    read_timeout: 120,
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

def current_main_revision
  stdout, stderr, status = Open3.capture3(
    "git",
    "ls-remote",
    UPSTREAM_URL,
    "refs/heads/main",
  )
  fail_with("git ls-remote failed: #{stderr.strip}") unless status.success?

  revision = stdout.lines.first.to_s.split.first
  fail_with("git ls-remote returned no main revision") unless revision&.match?(/\A[0-9a-f]{40}\z/)

  revision
end

def commit_date(revision, token)
  headers = {
    "Accept" => "application/vnd.github+json",
    "User-Agent" => "voiceink-homebrew-local",
  }
  headers["Authorization"] = "Bearer #{token}" unless token.nil? || token.empty?

  payload = JSON.parse(http_get(
    "https://api.github.com/repos/#{UPSTREAM_REPOSITORY}/commits/#{revision}",
    headers,
  ))
  timestamp = payload.dig("commit", "committer", "date") || payload.dig("commit", "author", "date")
  fail_with("GitHub commit #{revision} has no commit date") if timestamp.nil?

  Time.iso8601(timestamp).utc.strftime("%Y.%m.%d.%H%M%S")
rescue JSON::ParserError => e
  fail_with("invalid GitHub API response: #{e.message}")
end

cask = File.read(CASK_PATH)
current_revision_match = cask.match(/voiceink_upstream_revision\s*=\s*"([0-9a-f]{40})"/)
fail_with("cask has no voiceink_upstream_revision") if current_revision_match.nil?

latest_revision = current_main_revision
if current_revision_match[1] == latest_revision
  puts "VoiceInk cask is already at #{latest_revision}."
  exit 0
end

date = commit_date(latest_revision, ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"])
version = "#{date}-#{latest_revision[0, 8]}"
archive_url = "https://github.com/#{UPSTREAM_REPOSITORY}/archive/#{latest_revision}.tar.gz"
archive_sha256 = Digest::SHA256.hexdigest(http_get(
  archive_url,
  { "User-Agent" => "voiceink-homebrew-local" },
))

updated = cask.dup
updated.sub!(/(voiceink_upstream_revision\s*=\s*")[0-9a-f]{40}(")/) do
  "#{Regexp.last_match(1)}#{latest_revision}#{Regexp.last_match(2)}"
end
updated.sub!(/(^[ \t]*version[ \t]+")[^"]+(")/) do
  "#{Regexp.last_match(1)}#{version}#{Regexp.last_match(2)}"
end
updated.sub!(/(^[ \t]*sha256[ \t]+")[0-9a-f]{64}(")/) do
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

puts "Updated VoiceInk cask."
puts "  revision: #{latest_revision}"
puts "  version:  #{version}"
puts "  sha256:   #{archive_sha256}"
