# frozen_string_literal: true

require "date"
require "json"

class ReleasePreparation
  class Error < StandardError; end

  BUMPS = %w[major minor patch].freeze
  SECTIONS = %w[Added Changed Fixed Removed Security].freeze

  attr_reader :version

  def initialize(root: Dir.pwd)
    @root = root
    @config = JSON.parse(File.read(File.join(root, "config.json")))
    @version = @config["version"] if @config.is_a?(Hash)
    unless version.is_a?(String) && version.match?(/\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/)
      raise Error, "config.json must contain a major.minor.patch version"
    end
  end

  def next_version(bump)
    index = BUMPS.index(bump)
    raise Error, "Choose a major, minor, or patch bump" unless index

    parts = version.split(".").map(&:to_i)
    parts[index] += 1
    ((index + 1)...parts.length).each { |position| parts[position] = 0 }
    parts.join(".")
  end

  def self.validate_notes(notes)
    sections = {}
    current_section = nil

    notes.each_line(chomp: true) do |line|
      next if line.strip.empty?

      if line.start_with?("### ")
        current_section = line.delete_prefix("### ")
        unless SECTIONS.include?(current_section) && !sections.key?(current_section)
          raise Error, "Release notes contain an unsupported or duplicate section"
        end
        sections[current_section] = 0
      elsif current_section && line.match?(/\A- \S.*\z/)
        if line.match?(/\A- (TODO|TBD|placeholder|none|no changes)[.!]?\z/i)
          raise Error, "Release notes must not contain placeholders"
        end
        sections[current_section] += 1
      else
        raise Error, "Release notes must contain only ### sections and - bullets"
      end
    end

    if sections.empty? || sections.value?(0)
      raise Error, "Release notes must contain nonempty sections"
    end

    "#{notes.strip}\n"
  end

  def changes(bump, notes: nil, date: Date.today)
    new_version = next_version(bump)
    body = notes.nil? ? "### Added\n\n### Changed\n\n### Fixed\n" : self.class.validate_notes(notes)
    changelog_path = File.join(@root, "CHANGELOG.md")
    changelog = File.read(changelog_path)
    if changelog.match?(/^## \[#{Regexp.escape(new_version)}\]/)
      raise Error, "CHANGELOG.md already contains #{new_version}"
    end

    entry = "## [#{new_version}] - #{date.iso8601}\n\n#{body}\n"
    updated_changelog = if changelog.match?(/^## \[/)
      changelog.sub(/^## \[/) { "#{entry}## [" }
    else
      "#{changelog}\n#{entry}"
    end
    updated_config = JSON.pretty_generate(@config.merge("version" => new_version)) + "\n"

    {"config.json" => updated_config, "CHANGELOG.md" => updated_changelog}
  end

  def prepare(bump, notes: nil, date: Date.today)
    changes(bump, notes: notes, date: date).each do |path, content|
      File.write(File.join(@root, path), content)
    end
    next_version(bump)
  end
end
