# frozen_string_literal: true

# A year-planner view: the current month and the next 11 as rows, days 1-31 as
# columns, with multi-day events drawn as bars. The layout (lane packing and
# fitting event names) is done in the browser because it measures rendered text;
# the screenshot browser runs it before capturing. The output only depends on
# the date and the events, so the content hash only changes when they do.
class Devices::YearComponent < ViewComponent::Base
  def initialize(view_object:)
    @view_object = view_object
  end

  def today
    @view_object[:current_time].to_date
  end

  def events_json
    (@view_object[:year_events] || []).map { |event| event.to_h.symbolize_keys.slice(:title, :start, :end) }.to_json
  end
end
