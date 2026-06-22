# frozen_string_literal: true

# Persist the structured shipping address on locations so a saved location can
# be reused to ship additional devices without re-entering the address. Fields
# hold PII and are encrypted by the cloud Location extension.
#
# Existing locations are backfilled by geocoding their stored name (often a
# formatted address) via the configured Geocoder lookup (Google Places in
# production). The backfill is best-effort and never fails the migration.
class AddShippingAddressToLocations < ActiveRecord::Migration[8.1]
  def up
    add_column :locations, :line1, :text
    add_column :locations, :line2, :text
    add_column :locations, :city, :text
    add_column :locations, :state, :text
    add_column :locations, :postal_code, :text

    backfill_addresses
  end

  def down
    remove_column :locations, :line1
    remove_column :locations, :line2
    remove_column :locations, :city
    remove_column :locations, :state
    remove_column :locations, :postal_code
  end

  # Geocode each location's name into the structured address columns. Public so
  # it can be re-run for an already-migrated database (e.g. via a runner).
  def backfill_addresses
    return unless defined?(Geocoder)

    Location.reset_column_information
    Location.find_each do |location|
      next if location.city.present?

      result = Geocoder.search(location.name).first
      next unless result

      location.update(
        line1: street_line(result),
        city: result.try(:city),
        state: result.try(:state_code).presence || result.try(:state),
        postal_code: result.try(:postal_code),
        country_code: location.country_code.presence || result.try(:country_code)&.upcase
      )
    rescue => e
      Rails.logger.warn("Location address backfill skipped for ##{location.id}: #{e.class}: #{e.message}")
    end
  rescue => e
    Rails.logger.warn("Location address backfill skipped: #{e.class}: #{e.message}")
  end

  private

  def street_line(result)
    [result.try(:street_number), result.try(:route)].compact.join(" ").presence || result.try(:street_address)
  end
end
