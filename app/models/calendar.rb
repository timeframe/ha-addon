# frozen_string_literal: true

# A read-only calendar imported from Home Assistant. It exists to group events
# on the Events page and to anchor per-event customizations (icon/title/hide);
# events themselves are read live from Home Assistant, not stored here.
class Calendar < ActiveRecord::Base
  SOURCE_TYPE = "home_assistant"

  belongs_to :account
  has_many :event_customizations, class_name: "CalendarEventCustomization", dependent: :destroy

  validates :name, presence: true
  validates :external_id, presence: true

  def customization_for(customization_key)
    event_customizations.detect { |customization| customization.customization_key == customization_key }
  end
end
