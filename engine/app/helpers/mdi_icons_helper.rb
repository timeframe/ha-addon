# frozen_string_literal: true

require "json"

module MdiIconsHelper
  # simplecov:disable — load-time parsing of the shipped MDI css/meta data.
  MDI_ICONS = begin
    css_path = TimeframeCore::Engine.root.join("public", "css", "mdi", "materialdesignicons.css")
    css = File.read(css_path)
    css.scan(/\.(mdi-[a-z0-9-]+)::before/).flatten.uniq.sort
  end

  # Compact search index: { "mdi-icon-name" => "alias1 alias2 tag1 tag2" }
  # Only includes searchable keywords not already in the icon name itself.
  MDI_SEARCH_INDEX = begin
    meta_path = TimeframeCore::Engine.root.join("public", "data", "mdi_meta.json")
    if File.exist?(meta_path)
      css_set = Set.new(MDI_ICONS)
      meta = JSON.parse(File.read(meta_path))
      index = {}
      meta.each do |icon|
        mdi_name = "mdi-#{icon["name"]}"
        next unless css_set.include?(mdi_name)

        keywords = []
        (icon["aliases"] || []).each { |a| keywords << a.downcase }
        (icon["tags"] || []).each { |t| keywords << t.downcase }
        next if keywords.empty?

        index[mdi_name] = keywords.join(" ")
      end
      index
    else
      {}
    end
  end
  # simplecov:enable

  def mdi_icons_json
    MDI_ICONS.to_json.html_safe
  end

  def mdi_search_index_json
    MDI_SEARCH_INDEX.to_json.html_safe
  end

  # Render a calendar icon. If the icon is a single-letter MDI alpha icon
  # (e.g. "mdi-alpha-a"), render the letter as text instead of the MDI glyph.
  def calendar_icon_tag(icon, css_class: nil)
    icon = icon.to_s
    if (m = icon.match(/\Amdi-alpha-([a-z])\z/))
      classes = ["cal-letter", css_class].compact.join(" ")
      content_tag(:span, m[1].upcase, class: classes)
    else
      classes = ["mdi", icon, css_class].compact.reject(&:empty?).join(" ")
      content_tag(:span, "", class: classes)
    end
  end
end
