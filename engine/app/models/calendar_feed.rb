# frozen_string_literal: true

class CalendarFeed
  # Returns calendar events for a given UTC integer time range,
  # adding a `time` key for the time formatted for the user's timezone
  def events_for(starts_at, ends_at, events = [], device_name: nil, device_id: nil)
    filtered_events = events.compact.select do |event|
      if event.start_i == event.end_i
        [event.start_i, event.end_i].any? { (starts_at.to_i...ends_at.to_i).cover?(it) }
      else
        (event.start_i...event.end_i).overlaps?(starts_at.to_i...ends_at.to_i)
      end
    end.select { !it.omit? }.reject { it.hidden_for?(device_name, device_id: device_id) }

    # Merge duplicate events, merging the icon with a custom rule if so
    filtered_events = filtered_events.group_by { it.id }
      .map do |_k, v|
        if v.length > 1
          icons = v.map { |iv| iv.icon }
          icon =
            if icons.uniq.length == 1
              icons[0]
            elsif icons.include?("plus")
              "plus"
            else
              icons[0]
            end

          out = v[0]
          out.icon = icon
          out
        else
          v[0]
        end
      end

    # Primary de-duplication: collapse events that share a provider iCalendar
    # UID over the same time span (the one underlying event synced into several
    # calendars). Time is part of the key so the recurring instances of a series
    # (which all share a UID) stay separate; only same-instance copies merge.
    # The first occurrence wins, keeping its calendar's icon. Events without a
    # UID (weather, HA, birthdays, etc.) are left untouched for the backup pass.
    seen_uids = {}
    filtered_events = filtered_events.reject do |event|
      next false if event.ical_uid.blank?

      key = [event.ical_uid, event.start_i, event.end_i]
      seen_uids.key?(key).tap { seen_uids[key] = true }
    end

    # Backup de-duplication: collapse remaining exact look-alikes (same icon,
    # span, and summary) that don't carry a shared UID.
    filtered_events = filtered_events.uniq { [it.icon, it.start_i, it.end_i, it.summary] }

    daily_events = filtered_events.select(&:daily?)
    weather_daily, other_daily = daily_events.partition(&:weather?)

    {
      daily: weather_daily + other_daily,
      periodic: filtered_events
        .reject(&:daily?)
        .sort_by { |e| [e.start_i, (e.start_i == e.end_i) ? 0 : 1] }
    }
  end
end
