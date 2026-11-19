# frozen_string_literal: true

# Stable, provider-neutral types. Provider adapters translate their event codes
# to these IDs or labels; unrecognized events must remain enabled.
class WeatherAlertTypes
  IDS = %w[
    ashfall_advisory ashfall_warning avalanche_advisory avalanche_warning avalanche_watch
    blizzard_warning blizzard_watch blowing_dust_advisory blowing_dust_warning
    coastal_flood_advisory coastal_flood_statement coastal_flood_warning coastal_flood_watch
    cold_weather_advisory dense_fog_advisory dense_smoke_advisory drought_warning
    dust_advisory dust_storm_warning earthquake_warning excessive_heat_warning excessive_heat_watch
    extreme_cold_warning extreme_cold_watch extreme_heat_warning extreme_heat_watch
    extreme_wind_warning fire_warning fire_weather_watch flash_flood_statement
    flash_flood_warning flash_flood_watch flood_advisory flood_statement flood_warning flood_watch
    freeze_warning freeze_watch freezing_fog_advisory freezing_rain_advisory freezing_spray_advisory
    frost_advisory gale_warning gale_watch hard_freeze_warning hard_freeze_watch heat_advisory
    heavy_freezing_spray_warning heavy_freezing_spray_watch heavy_rain_warning heavy_rain_watch
    heavy_snow_warning heavy_snow_watch high_surf_advisory high_surf_warning high_wind_warning
    high_wind_watch hurricane_force_wind_warning hurricane_force_wind_watch hurricane_local_statement
    hurricane_warning hurricane_watch ice_storm_warning lake_effect_snow_advisory
    lake_effect_snow_warning lake_effect_snow_watch lakeshore_flood_advisory lakeshore_flood_statement
    lakeshore_flood_warning lakeshore_flood_watch low_water_advisory marine_weather_statement
    rain_advisory rain_warning rain_watch red_flag_warning rip_current_statement
    severe_thunderstorm_warning severe_thunderstorm_watch severe_weather_statement
    small_craft_advisory snow_advisory snow_squall_warning snow_warning snow_watch
    special_marine_warning special_weather_statement storm_surge_warning storm_surge_watch
    storm_warning storm_watch thunderstorm_warning thunderstorm_watch tornado_warning tornado_watch
    tropical_storm_warning tropical_storm_watch tsunami_advisory tsunami_warning tsunami_watch
    typhoon_warning typhoon_watch volcanic_eruption_warning wind_advisory wind_chill_advisory
    wind_chill_warning wind_chill_watch wind_warning wind_watch winter_storm_warning
    winter_storm_watch winter_weather_advisory
  ].freeze

  def self.options
    IDS.map { |id| [id.split("_").map(&:capitalize).join(" "), id] }.sort_by(&:first)
  end

  def self.normalize(value)
    id = value.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.gsub(/[^a-z0-9]+/, "_").sub(/\A_/, "").sub(/_\z/, "")
    id if IDS.include?(id)
  end

  def self.excluded?(type, excluded_ids:)
    id = normalize(type)
    !id.nil? && Array(excluded_ids).include?(id)
  end
end
