# frozen_string_literal: true

require "json"
require "yaml"

class MdiIconMatcher
  APP_ROOT = File.expand_path("../../..", __dir__)
  MAPPINGS_PATH = File.join(APP_ROOT, "config", "icon_mappings.yml")
  META_PATH = File.join(APP_ROOT, "engine", "public", "data", "mdi_meta.json")

  # Curated multi-word phrase overrides matched against the whole title (before
  # tokenized matching) for holidays/phrases that don't map to a single token.
  CURATED_PHRASES = [
    [/\b(independence day|fourth of july|4th of july)\b/, "firework"]
  ].freeze

  class << self
    def instance
      @instance ||= new
    end

    def match(text)
      instance.match(text)
    end

    def search(query)
      instance.search(query)
    end

    def reload!
      @instance = nil
    end
  end

  def initialize
    @custom_mappings = load_custom_mappings
    @meta = load_meta
    @css_icons = load_css_icons
    build_index
  end

  # Match an event summary to an icon name.
  # Returns icon name (without mdi- prefix) or nil.
  def match(text)
    return nil if text.nil? || text.strip.empty?

    # 0. Curated phrase overrides (e.g. "Independence Day" -> firework).
    lower = text.downcase
    CURATED_PHRASES.each { |pattern, icon| return icon if lower.match?(pattern) }

    words = tokenize(text)

    # 1. Check custom mappings first (highest priority)
    words.each do |word|
      if (icon = @custom_mappings[word])
        return icon if @css_icons.include?(icon)
      end
    end

    # 2. Try exact icon name match (e.g., "church" matches "church")
    words.each do |word|
      return word if @css_icons.include?(word) && @meta_names.include?(word)
    end

    # 3. Try alias match
    words.each do |word|
      if (icon = @alias_index[word])
        return icon if @css_icons.include?(icon)
      end
    end

    # 4. Try multi-word compound match against icon names
    # e.g., "ice cream" matches "ice-cream"
    if words.length >= 2
      (0...words.length - 1).each do |i|
        compound = "#{words[i]}-#{words[i + 1]}"
        return compound if @css_icons.include?(compound) && @meta_names.include?(compound)
      end
    end

    nil
  end

  # Search for icons matching a query (for the icon picker).
  # Returns array of icon names sorted by relevance.
  def search(query)
    return [] if query.nil? || query.strip.empty?

    lower = query.downcase.strip
    tokens = lower.split(/[\s-]+/)

    exact_name = []
    name_starts_with = []
    name_contains = []
    alias_matches = []
    tag_matches = []

    @meta.each do |icon|
      name = icon["name"]
      next unless @css_icons.include?(name)

      if name == lower || name == lower.tr(" ", "-")
        exact_name << name
      elsif name.start_with?(lower) || name.start_with?(lower.tr(" ", "-"))
        name_starts_with << name
      elsif name.include?(lower) || name.include?(lower.tr(" ", "-"))
        name_contains << name
      elsif Array(icon["aliases"]).any? { |a| a.downcase.include?(lower) }
        alias_matches << name
      elsif tokens.any? { |t| Array(icon["tags"]).any? { |tag| tag.downcase.include?(t) } }
        tag_matches << name
      end
    end

    exact_name + name_starts_with + name_contains + alias_matches + tag_matches
  end

  private

  def tokenize(text)
    text.downcase
      .gsub(/[^a-z0-9\s-]/, " ")
      .split(/[\s-]+/)
      .reject { |w| w.length < 2 }
      .uniq
  end

  def load_custom_mappings
    return {} unless File.exist?(MAPPINGS_PATH)

    YAML.safe_load_file(MAPPINGS_PATH) || {}
  # :nocov:
  rescue => e
    Rails.logger.warn("Failed to load icon mappings: #{e.message}") if defined?(Rails)
    {}
    # :nocov:
  end

  def load_meta
    return [] unless File.exist?(META_PATH)

    JSON.parse(File.read(META_PATH))
  # :nocov:
  rescue => e
    Rails.logger.warn("Failed to load MDI meta: #{e.message}") if defined?(Rails)
    []
    # :nocov:
  end

  def load_css_icons
    css_path = if defined?(TimeframeCore::Engine)
      TimeframeCore::Engine.root.join("public", "css", "mdi", "materialdesignicons.css")
    else
      # :nocov:
      File.expand_path("../../../public/css/mdi/materialdesignicons.css", __dir__)
      # :nocov:
    end

    return Set.new unless File.exist?(css_path)

    css = File.read(css_path)
    Set.new(css.scan(/\.(mdi-[a-z0-9-]+)::before/).flatten.map { |n| n.delete_prefix("mdi-") })
  end

  def build_index
    @meta_names = Set.new(@meta.map { |i| i["name"] })
    @alias_index = {}

    @meta.each do |icon|
      name = icon["name"]
      next unless @css_icons.include?(name)

      (icon["aliases"] || []).each do |al|
        key = al.downcase.tr("-", " ").strip
        # Keep first match (don't overwrite)
        key.split(/\s+/).each { |word| @alias_index[word] ||= name }
        @alias_index[key.tr(" ", "-")] ||= name
      end
    end
  end
end
