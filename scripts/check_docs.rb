# frozen_string_literal: true

require "open3"
require "optparse"
require "set"

REQUIRED_FILES = %w[
  README.md
  README.zh-CN.md
  docs/PRODUCT_SPEC.md
  docs/PRODUCT_SPEC.zh-CN.md
  AGENTS.md
  LICENSE
  CHANGELOG.md
  CODE_OF_CONDUCT.md
  CONTRIBUTING.md
  SECURITY.md
  SUPPORT.md
  .github/FUNDING.yml
].freeze

BILINGUAL_PAIRS = [
  ["README.md", "README.zh-CN.md"],
  ["docs/PRODUCT_SPEC.md", "docs/PRODUCT_SPEC.zh-CN.md"]
].freeze

TEXT_EXTENSIONS = %w[
  .cff .css .html .js .json .jsonc .lock .markdown .md .mjs .rb .rs .sh
  .toml .yaml .yml
].freeze
TEXT_FILENAMES = %w[.gitignore].freeze
UTF8_BOM = "\xEF\xBB\xBF".b.freeze

options = { root: Dir.pwd }
OptionParser.new do |parser|
  parser.on("--root PATH") { |path| options[:root] = path }
end.parse!

root = File.expand_path(options[:root])
errors = []
stdout, stderr, status = Open3.capture3(
  "git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"
)
unless status.success?
  warn "Unable to list repository files: #{stderr.strip}"
  exit 1
end

repository_files = stdout.split("\0").reject(&:empty?).to_set
REQUIRED_FILES.each do |path|
  errors << "Missing required file: #{path}" unless repository_files.include?(path) && File.file?(File.join(root, path))
end

BILINGUAL_PAIRS.each do |english, chinese|
  english_exists = repository_files.include?(english) && File.file?(File.join(root, english))
  chinese_exists = repository_files.include?(chinese) && File.file?(File.join(root, chinese))
  errors << "Missing bilingual pair: #{english}" unless english_exists
  errors << "Missing bilingual pair: #{chinese}" unless chinese_exists
end

funding_path = File.join(root, ".github/FUNDING.yml")
if repository_files.include?(".github/FUNDING.yml") && File.file?(funding_path)
  funding = File.read(funding_path, encoding: Encoding::UTF_8)
  errors << "Funding configuration must contain ko_fi: tinkora" unless funding.lines.any? { |line| line.strip == "ko_fi: tinkora" }
end

{
  "README.md" => "README.zh-CN.md",
  "README.zh-CN.md" => "README.md",
  "docs/PRODUCT_SPEC.md" => "PRODUCT_SPEC.zh-CN.md",
  "docs/PRODUCT_SPEC.zh-CN.md" => "PRODUCT_SPEC.md"
}.each do |path, target|
  absolute_path = File.join(root, path)
  next unless repository_files.include?(path) && File.file?(absolute_path)

  content = File.read(absolute_path, encoding: Encoding::UTF_8)
  errors << "#{path} must link to #{target}" unless content.include?("](#{target})")
end

%w[README.md README.zh-CN.md].each do |path|
  absolute_path = File.join(root, path)
  next unless repository_files.include?(path) && File.file?(absolute_path)

  content = File.read(absolute_path, encoding: Encoding::UTF_8)
  errors << "#{path} must include https://ko-fi.com/tinkora" unless content.include?("https://ko-fi.com/tinkora")
end

text_files = repository_files.select do |path|
  TEXT_EXTENSIONS.include?(File.extname(path).downcase) ||
    TEXT_FILENAMES.include?(File.basename(path)) ||
    REQUIRED_FILES.include?(path)
end

text_files.sort.each do |path|
  absolute_path = File.join(root, path)
  next unless File.file?(absolute_path)

  content = File.binread(absolute_path)
  errors << "UTF-8 BOM is not allowed: #{path}" if content.start_with?(UTF8_BOM)
  errors << "Invalid UTF-8: #{path}" unless content.force_encoding(Encoding::UTF_8).valid_encoding?
rescue SystemCallError => error
  errors << "Unable to read #{path}: #{error.message}"
end

if errors.empty?
  puts "Documentation checks passed (#{text_files.length} repository text files scanned)."
  exit 0
end

errors.each { |error| warn error }
exit 1
