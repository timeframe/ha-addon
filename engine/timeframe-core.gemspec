# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "timeframe-core"
  spec.version = "0.1.0"
  spec.authors = ["Joel Hawksley"]
  spec.summary = "Shared engine for Timeframe e-ink display apps"

  spec.files = Dir["{app,config,db,lib,public}/**/*", "LICENSE.md"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 4.0"

  spec.add_dependency "rails", "~> 8"
  spec.add_dependency "pg"
  spec.add_dependency "propshaft"
  spec.add_dependency "ferrum"
  spec.add_dependency "mini_magick"
  spec.add_dependency "extlz4"
  spec.add_dependency "view_component"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "minitest-mock"
  spec.add_development_dependency "overcommit"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "standard"
  spec.add_development_dependency "capybara"
  spec.add_development_dependency "cuprite"
  spec.add_development_dependency "good_job"
  spec.add_development_dependency "puma"
  spec.add_development_dependency "warden"
end
