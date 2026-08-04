# frozen_string_literal: true

# Upserts the account's read-only Calendar records from the Home Assistant
# calendar entities and prunes calendars that no longer exist in HA. Events are
# not stored; they are read live from Home Assistant.
class HomeAssistantCalendarImport
  def initialize(account:, api: HomeAssistantApi.new)
    @account = account
    @api = api
  end

  def call
    seen_ids = @api.calendar_entities.map do |entity|
      calendar = @account.calendars.find_or_initialize_by(external_id: entity[:entity_id])
      calendar.update!(name: entity[:name], icon: entity[:icon], source_type: Calendar::SOURCE_TYPE)
      calendar.id
    end
    @account.calendars.where.not(id: seen_ids).destroy_all
  end
end
