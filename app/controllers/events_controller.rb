# frozen_string_literal: true

# Read-only Events page for the add-on. Lists upcoming Home Assistant calendar
# events grouped by calendar and lets the user customize each event's icon,
# title, or hide it. Customizations are stored locally and applied on the
# rendered device (see HomeAssistantApi#calendar_events).
class EventsController < ApplicationController
  def index
    @account = current_user.accounts.first
    @calendars = @account.calendars.includes(:event_customizations).order(:name)
    @devices = @account.devices.order(:name).map { |device| {id: device.id, name: device.name} }
    by_external = @calendars.index_by(&:external_id)
    api = HomeAssistantApi.new(account: @account)
    @timezone = api.time_zone
    @rows = api.calendar_events.filter_map do |event|
      calendar = by_external[event.entity_id]
      {event: event, calendar: calendar} if calendar
    end
  end

  def update_customization
    customization = find_customization
    customization.assign_attributes(
      icon: params.dig(:customization, :icon).presence&.delete_prefix("mdi-"),
      title_override: params.dig(:customization, :title_override).presence,
      only_tokens: Array(params[:device_ids]).map(&:to_s),
      banner_enabled: params[:banner] == "1",
      banner_message: params[:message].presence,
      countdown_days: countdown_days_param
    )
    persist_customization(customization)
    redirect_to events_path, notice: "Event updated."
  end

  def toggle_omit
    customization = find_customization
    customization.omit = params[:omit] == "1"
    persist_customization(customization)
    redirect_to events_path
  end

  def bulk_hide
    @account = current_user.accounts.first
    Array(params[:calendar_event_ids]).each do |token|
      calendar_id, key = token.to_s.split("::", 2)
      next if key.blank?

      calendar = @account.calendars.find_by(id: calendar_id)
      next unless calendar

      calendar.event_customizations.find_or_initialize_by(customization_key: key).update!(omit: true)
    end
    redirect_to events_path, notice: "Events hidden."
  end

  private

  def find_customization
    @account = current_user.accounts.first
    calendar = @account.calendars.find(params[:calendar_id])
    calendar.event_customizations.find_or_initialize_by(customization_key: params[:customization_key])
  end

  def persist_customization(customization)
    if customization.blank_customization?
      customization.destroy if customization.persisted?
    else
      customization.save!
    end
  end

  def countdown_days_param
    return nil unless params[:countdown] == "1"

    days = params[:countdown_days].to_i
    days.positive? ? days : nil
  end
end
