# frozen_string_literal: true

# Read tokens from logical text lines, but edit the original text/HTML rather
# than writing the lossy text projection back to a provider.
class EventDescription
  PATTERNS = {
    title: /timeframe-title:([^\r\n]+)/,
    icon: /timeframe-icon:(?:mdi-)?([a-z0-9][a-z0-9-]*)/i,
    only: /timeframe-only:([^\r\n]+)/,
    omit: /timeframe-omit/,
    banner: /timeframe-banner|#banner/,
    countdown: /timeframe-countdown:(\d{1,3})/i
  }.freeze
  BLOCKS = %w[address article aside blockquote div dl dt dd fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section table tr td th ul].freeze
  INVISIBLE = %w[head script style template noscript title].freeze

  def initialize(description, case_insensitive: false)
    @raw = description
    @case_insensitive = case_insensitive
  end

  def html?
    @html ||= @raw.to_s.scan(/<\/?([a-z][a-z0-9]*)\b/i).any? do |name|
      Nokogiri::HTML4::ElementDescription[name.first.downcase]
    end
  end

  def title_override
    value(:title)&.strip.presence
  end

  def icon
    value(:icon)
  end

  def only_tokens
    value(:only).to_s.split(",").map(&:strip)
  end

  def omit?
    matches(:omit).any?
  end

  def banner?
    matches(:banner).any?
  end

  def countdown_days
    days = value(:countdown).to_i
    days if days.positive?
  end

  def without_tokens(*names)
    names = PATTERNS.keys if names.empty?
    names.each { |name| PATTERNS.fetch(name) }
    return @raw unless names.any? { |name| matches(name).any? }

    self.class.new(@raw, case_insensitive: @case_insensitive).send(:remove_tokens, names)
  end

  def append(tokens, separator: "\n")
    return @raw if tokens.empty?

    if html?
      @raw + tokens.map { |token| "<div>#{ERB::Util.html_escape(token)}</div>" }.join
    else
      [@raw, *tokens].compact.reject(&:empty?).join(separator)
    end
  end

  private

  def value(name)
    matches(name).first&.[](1)
  end

  def matches(name)
    @matches ||= {}
    @matches[name] ||= begin
      project unless @text
      pattern = PATTERNS.fetch(name)
      pattern = Regexp.new(pattern.source, pattern.options | Regexp::IGNORECASE) if @case_insensitive
      @text.to_enum(:scan, pattern).map { Regexp.last_match }
    end
  end

  def project
    @text = +""
    @segments = []
    if html?
      @document = Loofah.fragment(@raw)
      @document.children.each { |node| project_node(node) }
    else
      @text = @raw.to_s
    end
  end

  def project_node(node)
    if node.text?
      @segments << [node, @text.length, node.content.length]
      @text << node.content
    elsif node.element? && !INVISIBLE.include?(node.name)
      boundary = node.name == "br" || BLOCKS.include?(node.name)
      @text << "\n" if boundary
      node.children.each { |child| project_node(child) }
      @text << "\n" if boundary
    end
  end

  def remove_tokens(names)
    ranges = names.flat_map { |name| matches(name).map { |match| match.begin(0)...match.end(0) } }
    ranges = ranges.sort_by(&:begin).each_with_object([]) do |range, merged|
      if merged.any? && range.begin <= merged.last.end
        merged[-1] = merged.last.begin...[merged.last.end, range.end].max
      else
        merged << range
      end
    end
    if html?
      @segments.each do |node, start, length|
        content = node.content.dup
        ranges.sort_by(&:begin).reverse_each do |range|
          first = [range.begin - start, 0].max
          last = [range.end - start, length].min
          content[first...last] = "" if first < last
        end
        node.content = content
      end
      @document.to_html
    else
      text = @raw.dup
      ranges.sort_by(&:begin).reverse_each { |range| text[range] = "" }
      text
    end
  end
end
