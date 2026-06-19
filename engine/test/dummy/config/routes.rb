# frozen_string_literal: true

require_relative "application"
Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  root to: "dashboard#index"
  get "pair", to: "setup#index"
  post "claim_device", to: "dashboard#claim_device", as: :claim_device
  get "test_sign_in", to: "test_sessions#sign_in"

  resources :accounts, only: [] do
    resources :locations, only: [:create, :destroy] do
      resources :devices, only: [:create, :show, :update, :destroy] do
        get :confirmation_image, on: :member
        get :screenshot, on: :member
        get :preview_frame, on: :member
        get :settings, on: :member
        patch :update_template, on: :member
        patch :update_configuration, on: :member
        patch :update_options, on: :member
        patch :rename, on: :member
        post :regenerate_tokens, on: :member
        post :repair, on: :member
        post :client_log, on: :member
      end
    end
  end

  get "d/:id", to: "token_devices#show", as: :token_device
  get "d/:id/screenshot", to: "token_devices#screenshot", as: :token_device_screenshot
  get "signed_screenshot/:sgid", to: "signed_screenshots#show", as: :signed_screenshot

  namespace :api, defaults: {format: :json} do
    get :setup, to: "trmnl#setup"
    get :display, to: "trmnl#display"
    post :log, to: "trmnl#log"
  end
end
