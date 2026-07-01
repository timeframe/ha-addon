# frozen_string_literal: true

# Tracks application uptime via a per-minute heartbeat. A background job inserts
# one row each minute (see RecordUptimeJob in each app). A missing minute means
# the app was down, so uptime is measured as recorded minutes divided by the
# minutes that should have been recorded.
class UptimeCheck < ActiveRecord::Base
  RETENTION_PERIOD = 90.days

  # Windows shown on the status page: [label, duration], longest last.
  WINDOWS = [
    ["24 hours", 24.hours],
    ["7 days", 7.days],
    ["30 days", 30.days],
    ["90 days", 90.days]
  ].freeze

  # A heartbeat is considered live if one was recorded in the last 2 minutes
  # (one full minute of slack beyond the current, possibly-unrecorded minute).
  LIVE_THRESHOLD = 2.minutes

  scope :within, ->(range) { where(recorded_at: range) }

  # Current operational state for the status banner:
  #   :operational — recent heartbeat, all checks healthy
  #   :degraded    — recent heartbeat, but last check unhealthy
  #   :down        — no heartbeat in the last LIVE_THRESHOLD
  def self.current_state
    last = order(recorded_at: :desc).first
    return :down if last.nil? || last.recorded_at < LIVE_THRESHOLD.ago

    last.healthy? ? :operational : :degraded
  end

  # Records (or updates) the heartbeat for the current minute. Idempotent: the
  # unique index on recorded_at means at most one row exists per minute. The
  # optional status snapshot (e.g. SystemStatus.compute) is stored so the admin
  # status page can show which checks were failing for an unhealthy minute.
  def self.record!(healthy: true, status: nil, at: Time.current)
    minute = at.utc.beginning_of_minute
    check = find_or_initialize_by(recorded_at: minute)
    check.healthy = healthy
    check.status_data = status if status
    check.save!
    check
  rescue ActiveRecord::RecordNotUnique
    # A concurrent worker inserted the same minute first; the row exists.
    find_by(recorded_at: minute)
  end

  # Percentage (0–100) of expected minutes that have a heartbeat over the given
  # window. The window is floored at the first-ever record so time before the
  # feature launched is not counted as downtime. The current (incomplete) minute
  # is excluded. Returns 100.0 when there is not yet enough data to measure.
  def self.uptime_percentage(window)
    bounds = window_bounds(window)
    return 100.0 unless bounds

    start_minute, end_minute = bounds
    expected = minute_span(start_minute, end_minute)
    present = within(start_minute..end_minute).count
    [(present.to_f / expected * 100).round(3), 100.0].min
  end

  # One entry per calendar day for the last `days` days (oldest first), used to
  # render the historical uptime bar. Each entry:
  #   { date:, status:, uptime_pct:, present:, expected:, healthy: }
  # status is :up (full + healthy), :degraded (full but some unhealthy),
  # :down (missing minutes), or :no_data (outside the recorded range).
  def self.daily_summary(days: 90)
    first_minute = minimum(:recorded_at)
    today = Time.current.utc.to_date
    start_date = today - (days - 1)
    return (start_date..today).map { |date| {date: date, status: :no_data, uptime_pct: nil, present: 0, expected: 0, healthy: 0} } unless first_minute

    last_minute = (Time.current.utc - 1.minute).beginning_of_minute
    range_start = start_date.beginning_of_day.utc
    present_by_date = within(range_start..last_minute).group(Arel.sql("DATE(recorded_at)")).count.transform_keys(&:to_date)
    healthy_by_date = within(range_start..last_minute).where(healthy: true).group(Arel.sql("DATE(recorded_at)")).count.transform_keys(&:to_date)

    (start_date..today).map do |date|
      effective_start = [date.beginning_of_day.utc, first_minute].max
      effective_end = [(date + 1).beginning_of_day.utc - 1.minute, last_minute].min

      if effective_start > effective_end
        next {date: date, status: :no_data, uptime_pct: nil, present: 0, expected: 0, healthy: 0}
      end

      expected = minute_span(effective_start, effective_end)
      present = present_by_date[date] || 0
      healthy = healthy_by_date[date] || 0
      uptime_pct = [(present.to_f / expected * 100).round(3), 100.0].min

      status =
        if present < expected
          :down
        elsif healthy < present
          :degraded
        else
          :up
        end

      {date: date, status: status, uptime_pct: uptime_pct, present: present, expected: expected, healthy: healthy}
    end
  end

  # Number of minute slots between two minute-aligned timestamps, inclusive.
  def self.minute_span(start_minute, end_minute)
    ((end_minute - start_minute) / 60).round + 1
  end

  # [start_minute, end_minute] to measure, or nil when there is no completed
  # minute in range yet (e.g. the very first minute the feature is live).
  def self.window_bounds(window)
    first_minute = minimum(:recorded_at)
    return nil unless first_minute

    end_minute = (Time.current.utc - 1.minute).beginning_of_minute
    window_start = (Time.current.utc - window).beginning_of_minute
    start_minute = [window_start, first_minute].max
    return nil if start_minute > end_minute

    [start_minute, end_minute]
  end

  private_class_method :minute_span, :window_bounds
end
