# frozen_string_literal: true

class HealthProbe < ActiveRecord::Base
  validates :key, presence: true, uniqueness: true

  def self.record_success!(key, details: {})
    record!(key, successful: true, details: details)
  end

  def self.record_failure!(key, error)
    record!(
      key,
      successful: false,
      details: {error: {class: error.class.name, message: error.message}}
    )
  end

  def self.record!(key, successful:, details:)
    transaction do
      probe = lock.find_or_initialize_by(key: key)
      probe.successful = successful
      probe.consecutive_failures = successful ? 0 : probe.consecutive_failures + 1
      probe.checked_at = Time.current
      probe.details = details
      probe.save!
      probe
    end
  end

  private_class_method :record!
end
