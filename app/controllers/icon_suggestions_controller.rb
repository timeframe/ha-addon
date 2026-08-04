# frozen_string_literal: true

# Returns an auto-assigned icon for event text, powering the icon picker's
# "Use suggested icon" button on the Events page.
class IconSuggestionsController < ApplicationController
  def show
    match = MdiIconMatcher.match(params[:text].to_s)
    render json: {icon: match ? "mdi-#{match}" : nil}
  end
end
