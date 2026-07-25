# frozen_string_literal: true

# Caches the most recent Open-Meteo air-quality forecast (hourly US AQI) for a
# location, mirroring weather_syncs, so devices can render air-quality alert
# events without hitting the upstream API on every render.
class CreateAirQualitySyncs < ActiveRecord::Migration[8.1]
  def change
    create_table :air_quality_syncs do |t|
      t.bigint :location_id, null: false
      t.jsonb :response_data, null: false
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :air_quality_syncs, [:location_id, :fetched_at]
  end
end
