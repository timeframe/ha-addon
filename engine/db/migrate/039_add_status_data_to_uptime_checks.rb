# frozen_string_literal: true

# Snapshots the SystemStatus JSON alongside each per-minute uptime heartbeat so
# the admin status page can show exactly which checks were failing for any
# unhealthy minute.
class AddStatusDataToUptimeChecks < ActiveRecord::Migration[8.1]
  def change
    add_column :uptime_checks, :status_data, :jsonb
  end
end
