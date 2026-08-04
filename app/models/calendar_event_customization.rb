# frozen_string_literal: true

# A locally-stored customization (icon, title override, hide, device-only) for a
# read-only Home Assistant calendar event. Keyed by (calendar_id,
# customization_key) where the key is the event's Home Assistant id/uid, so it
# survives the live event list changing and is shared across a recurring series.
#
# The customization is expressed as "timeframe-*" description tokens which
# DeviceEvent already understands, so it applies both on the Events page and on
# the rendered device (see HomeAssistantApi#calendar_events).
class CalendarEventCustomization < ActiveRecord::Base
  belongs_to :calendar

  encrypts :title_override
  encrypts :banner_message

  validates :customization_key, presence: true, uniqueness: {scope: :calendar_id}

  def only_token_list
    Array(only_tokens).map(&:to_s)
  end

  # True when the record holds nothing, so callers can delete it instead of
  # persisting an empty row.
  def blank_customization?
    icon.blank? && title_override.blank? && !omit && only_token_list.empty? &&
      countdown_days.blank? && !banner_enabled
  end

  # Merge this customization onto a source description. Tokens are prepended so
  # DeviceEvent's first-match parsing prefers them over any tokens already in the
  # Home Assistant event description. When a banner is enabled the banner message
  # replaces the body (DeviceEvent renders the token-stripped remainder).
  def merged_description(description)
    body = (banner_enabled && banner_message.present?) ? banner_message : description
    [token_string, body].reject(&:blank?).join("\n")
  end

  def token_string
    tokens = []
    tokens << "timeframe-icon:mdi-#{icon}" if icon.present?
    tokens << "timeframe-title:#{title_override}" if title_override.present?
    tokens << "timeframe-only:#{only_token_list.join(",")}" if only_token_list.any?
    tokens << "timeframe-countdown:#{countdown_days}" if countdown_days.present?
    tokens << "timeframe-banner" if banner_enabled
    tokens << "timeframe-omit" if omit
    tokens.join("\n")
  end
end
