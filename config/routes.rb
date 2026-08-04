# frozen_string_literal: true

Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  root to: "dashboard#index"
  get "pair", to: "setup#index"
  get "status", to: "status#index"
  get "settings", to: "settings#show"
  patch "settings", to: "settings#update"
  get "events", to: "events#index"
  get "icon_suggestion", to: "icon_suggestions#show", as: :icon_suggestion
  patch "events/customization", to: "events#update_customization", as: :event_customization
  patch "events/toggle_omit", to: "events#toggle_omit", as: :toggle_omit_event
  patch "events/bulk_hide", to: "events#bulk_hide", as: :bulk_hide_events
  get "onboarding", to: "onboarding#show", as: :onboarding
  post "onboarding/device", to: "onboarding#create_device", as: :onboarding_device
  post "onboarding/pair", to: "onboarding#pair", as: :onboarding_pair
  patch "onboarding/layout", to: "onboarding#set_layout", as: :onboarding_layout
  post "onboarding/back", to: "onboarding#back", as: :onboarding_back
  post "claim_device", to: "dashboard#claim_device", as: :claim_device

  get "test_sign_in", to: "test_sessions#sign_in" if Rails.env.test?

  resources :accounts, only: [:create, :destroy] do
    resources :locations, only: [:create, :destroy] do
      resources :devices, only: [:create, :show, :update, :destroy] do
        get :confirmation_image, on: :member
        get :screenshot, on: :member
        get :preview_frame, on: :member
        get :settings, on: :member
        patch :update_template, on: :member
        patch :update_configuration, on: :member
        patch :update_calendars, on: :member
        patch :update_options, on: :member
        patch :rename, on: :member
        post :regenerate_tokens, on: :member
        post :repair, on: :member
        post :client_log, on: :member
      end
    end
  end

  # Token-authenticated display routes for sessionless devices
  get "d/:id", to: "token_devices#show", as: :token_device
  get "d/:id/screenshot", to: "token_devices#screenshot", as: :token_device_screenshot

  # Signed, expiring screenshot URLs for TRMNL devices
  get "signed_screenshot/:sgid", to: "signed_screenshots#show", as: :signed_screenshot

  mount GoodJob::Engine => "/good_job"

  namespace :api, defaults: {format: :json} do
    get :setup, to: "trmnl#setup"
    get :display, to: "trmnl#display"
    post :log, to: "trmnl#log"
  end
end
