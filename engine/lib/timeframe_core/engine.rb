# frozen_string_literal: true

module TimeframeCore
  class Engine < ::Rails::Engine
    config.autoload_paths << root.join("app", "lib")

    initializer "timeframe_core.view_component" do |app|
      ActiveSupport.on_load(:view_component) do
        ViewComponent::Base.config.generate.path = TimeframeCore::Engine.root.join("app", "components")
      end
    end

    initializer "timeframe_core.append_migrations" do |app|
      unless app.root.to_s.match?(root.to_s)
        config.paths["db/migrate"].expanded.each do |expanded_path|
          app.config.paths["db/migrate"] << expanded_path
        end
      end
    end

    initializer "timeframe_core.inflections" do
      Rails.autoloaders.each do |autoloader|
        autoloader.inflector.inflect("lz4_block" => "LZ4Block")
      end
    end

    initializer "timeframe_core.assets" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.paths << root.join("app", "assets", "stylesheets")
        app.config.assets.paths << root.join("app", "assets", "builds")
        app.config.assets.paths << root.join("app", "assets", "config")
      end
    end

    initializer "timeframe_core.static_assets" do |app|
      app.middleware.insert_before(::ActionDispatch::Static, ::ActionDispatch::Static, root.join("public").to_s)
    end
  end
end
