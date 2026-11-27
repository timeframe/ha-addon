# frozen_string_literal: true

class HaSensorState
  def self.parts(state)
    return [] if state.blank? || %w[unavailable unknown].include?(state.strip)

    state.split("\n").each_with_index.filter_map do |line, line_index|
      next if line.strip.empty?
      parts = line.split(",").map(&:strip)
      next if parts.empty?
      [parts, line_index]
    end
  end
end
