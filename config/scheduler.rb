scheduler = Rufus::Scheduler.new

api = HomeAssistantApi.new
api.fetch_config

# Fetch states every 2 seconds for near-real-time updates
scheduler.every "2s" do
  HomeAssistantApi.new.fetch_states
  DeviceBroadcaster.broadcast_all_mira_devices
end

# Fetch calendars and weather on startup
scheduler.in "5s" do
  api = HomeAssistantApi.new
  api.fetch_calendars
  api.fetch_year_calendars
  api.fetch_weather
  HomeAssistantCalendarImport.new(account: Account.first).call if Account.first
  DeviceBroadcaster.broadcast_all_mira_devices
end

scheduler.every "5m" do
  HomeAssistantApi.new.fetch_config
  DeviceBroadcaster.broadcast_all_mira_devices
end

scheduler.every "1m" do
  HomeAssistantApi.new.fetch_calendars
  HomeAssistantCalendarImport.new(account: Account.first).call if Account.first
  DeviceBroadcaster.broadcast_all_mira_devices
end

# The Year template's calendars cover the next 12 months, so they're fetched
# less often than the short-range ones, but often enough that a newly added
# trip shows up within a refresh or two.
scheduler.every "15m" do
  HomeAssistantApi.new.fetch_year_calendars
end

scheduler.every "1m" do
  HomeAssistantApi.new.fetch_weather
  DeviceBroadcaster.broadcast_all_mira_devices
end

scheduler.join
