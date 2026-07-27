# frozen_string_literal: true

class Devices::StatusBarComponent < ViewComponent::Base
  def initialize(view_object:)
    @view_object = view_object
  end

  def render?
    @view_object[:top_left].any? || @view_object[:top_right].any? || @view_object[:weather_status].any? || @view_object[:battery].present?
  end

  # Consolidated top-left indicators (top_left + weather_status). Grouping
  # merges items that share an icon (and rotation) so "LOCK Front, LOCK Back"
  # renders as a single "LOCK Front, Back".
  def left_groups
    consolidate(@view_object[:top_left] + @view_object[:weather_status])
  end

  # Consolidated top-right indicators.
  def right_groups
    consolidate(@view_object[:top_right])
  end

  private

  # Merges items sharing the same icon (and rotation) into one group, joining
  # their labels with ", " while preserving first-seen order.
  def consolidate(items)
    items.each_with_object([]) do |item, groups|
      group = groups.find { |g| g[:icon] == item[:icon] && g[:rotation] == item[:rotation] }
      label = item[:label].to_s
      if group
        group[:labels] << label if label.present?
      else
        groups << {icon: item[:icon], rotation: item[:rotation], labels: (label.present? ? [label] : [])}
      end
    end
  end
end
