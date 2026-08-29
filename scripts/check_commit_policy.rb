# frozen_string_literal: true

require "open3"
require "optparse"

ORGANIZATION_NAMES = ["tinkeragora", "Tinker Agora"].freeze
ORGANIZATION_EMAIL = "314183062+tinkeragora@users.noreply.github.com"
BOT_NAME = /\A.+\[bot\]\z/
BOT_EMAIL = /\A\d+\+.+\[bot\]@users\.noreply\.github\.com\z/
HAN_TEXT = /\p{Han}/
RECORD_SEPARATOR = "\x1E"
FIELD_SEPARATOR = "\x1F"

def allowed_identity?(name, email)
  return true if ORGANIZATION_NAMES.include?(name) && email == ORGANIZATION_EMAIL
  return true if name == "GitHub" && email == "noreply@github.com"

  name.match?(BOT_NAME) && email.match?(BOT_EMAIL)
end

options = { root: Dir.pwd }
OptionParser.new do |parser|
  parser.on("--root PATH") { |path| options[:root] = path }
end.parse!

root = File.expand_path(options[:root])
format = ["%x1e%H", "%an", "%ae", "%cn", "%ce", "%s", "%b"].join("%x1f")

stdout, stderr, status = Open3.capture3("git", "-C", root, "log", "HEAD", "--format=#{format}")
unless status.success?
  warn "Unable to inspect commit history: #{stderr.strip}"
  exit 1
end

errors = []
stdout.split(RECORD_SEPARATOR).reject(&:empty?).each do |record|
  sha, author_name, author_email, committer_name, committer_email, subject, body =
    record.split(FIELD_SEPARATOR, 7)
  sha = sha.to_s.strip

  errors << "#{sha}: author identity is not allowed" unless allowed_identity?(author_name, author_email)
  errors << "#{sha}: committer identity is not allowed" unless allowed_identity?(committer_name, committer_email)

  message = [subject, body].compact.join("\n")
  errors << "#{sha}: commit message must not contain Han characters" if message.match?(HAN_TEXT)
end

if errors.empty?
  puts "Commit policy checks passed."
  exit 0
end

errors.each { |error| warn error }
exit 1
