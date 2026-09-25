#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "open3"
require "uri"

UPSTREAM_REPOSITORY = "chigwell/telegram-mcp"
UPSTREAM_URL = "https://github.com/#{UPSTREAM_REPOSITORY}.git"
FORMULA_PATH = File.expand_path("../Formula/telegram-mcp-source.rb", __dir__)

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

def github_headers
  headers = {
    "Accept" => "application/vnd.github+json",
    "User-Agent" => "medovukha-telegram-mcp-updater",
  }
  token = ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"]
  headers["Authorization"] = "Bearer #{token}" unless token.nil? || token.empty?
  headers
end

def latest_release
  JSON.parse(http_get(
    "https://api.github.com/repos/#{UPSTREAM_REPOSITORY}/releases/latest",
    github_headers,
  ))
rescue JSON::ParserError => e
  fail_with("invalid GitHub release response: #{e.message}")
end

def tag_revision(tag)
  stdout, stderr, status = Open3.capture3(
    "git",
    "ls-remote",
    "--tags",
    "--refs",
    UPSTREAM_URL,
    "refs/tags/#{tag}",
  )
  fail_with("git ls-remote failed: #{stderr.strip}") unless status.success?

  revision = stdout.lines.first.to_s.split.first
  fail_with("git ls-remote returned no revision for tag #{tag}") unless revision&.match?(/\A[0-9a-f]{40}\z/)

  revision
end

formula = File.read(FORMULA_PATH)
current_tag_match = formula.match(/telegram_mcp_upstream_tag\s*=\s*"([^"]+)"/)
fail_with("formula has no telegram_mcp_upstream_tag") if current_tag_match.nil?
current_revision_match = formula.match(/telegram_mcp_upstream_revision\s*=\s*"([0-9a-f]{40})"/)
fail_with("formula has no telegram_mcp_upstream_revision") if current_revision_match.nil?

release = latest_release
release_tag = release["tag_name"].to_s
fail_with("latest release has no v-prefixed semantic version tag") unless release_tag.match?(/\Av\d+\.\d+\.\d+\z/)
latest_revision = tag_revision(release_tag)

if current_tag_match[1] == release_tag && current_revision_match[1] == latest_revision
  puts "Telegram MCP formula is already at #{release_tag} (#{latest_revision})."
  exit 0
end

archive_url = "https://github.com/#{UPSTREAM_REPOSITORY}/archive/refs/tags/#{release_tag}.tar.gz"
archive_sha256 = Digest::SHA256.hexdigest(http_get(
  archive_url,
  { "User-Agent" => "medovukha-telegram-mcp-updater" },
))

updated = formula.dup
updated.sub!(/(telegram_mcp_upstream_tag\s*=\s*")[^"]+(")/) do
  "#{Regexp.last_match(1)}#{release_tag}#{Regexp.last_match(2)}"
end
updated.sub!(/(telegram_mcp_upstream_revision\s*=\s*")[0-9a-f]{40}(")/) do
  "#{Regexp.last_match(1)}#{latest_revision}#{Regexp.last_match(2)}"
end
updated.sub!(/(^[ \t]*sha256[ \t]+\")[0-9a-f]{64}(\")/) do
  "#{Regexp.last_match(1)}#{archive_sha256}#{Regexp.last_match(2)}"
end

fail_with("formula update markers were incomplete") if updated == formula

temporary_path = "#{FORMULA_PATH}.tmp.#{$$}"
begin
  File.write(temporary_path, updated)
  File.rename(temporary_path, FORMULA_PATH)
ensure
  File.delete(temporary_path) if File.file?(temporary_path)
end

puts "Updated Telegram MCP formula."
puts "  release:  #{release_tag}"
puts "  revision: #{latest_revision}"
puts "  sha256:   #{archive_sha256}"
