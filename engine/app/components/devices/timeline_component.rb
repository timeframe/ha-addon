# frozen_string_literal: true

class Devices::TimelineComponent < ViewComponent::Base
  def initialize(view_object:, compact_header: false)
    @view_object = view_object
    @compact_header = compact_header
  end

  def event_icon(event)
    if event[:icon_text]
      content_tag(:span, event[:icon_text])
    elsif event[:icon_style]
      content_tag(:i, "", class: "mdi mdi-#{event[:icon_class]}", style: event[:icon_style])
    else
      content_tag(:i, "", class: "mdi mdi-#{event[:icon_class]}")
    end
  end

  def event_summary_html(event)
    parts = [ERB::Util.html_escape(event[:summary])]
    Array(event[:precip]).each do |p|
      segments = ["/"]
      segments << content_tag(:i, "", class: "mdi mdi-#{p[:icon]}") if p[:icon]
      segments << ERB::Util.html_escape(p[:label])
      parts << segments.join(" ")
    end
    if event[:wind_gust]
      parts << "/ #{content_tag(:i, "", class: "mdi mdi-weather-windy")} #{ERB::Util.html_escape(event[:wind_gust])}"
    end
    parts.join(" ").html_safe
  end
end
