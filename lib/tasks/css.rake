# frozen_string_literal: true

# Builds ha-addon's Tailwind bundle. Kept separate from the (legacy) dartsass
# pipeline that compiles Bootstrap into application.css, so the migrated
# Tailwind layout can load only Tailwind. Hooks into assets:precompile.
namespace :css do
  INPUT = "application.tailwind.css"
  OUTPUT = "application_tailwind.css"

  def tailwind_command(*extra)
    require "tailwindcss/ruby"

    input = Rails.root.join("app/assets/stylesheets", INPUT)
    output = Rails.root.join("app/assets/builds", OUTPUT)
    [Tailwindcss::Ruby.executable.to_s, "--input", input.to_s, "--output", output.to_s, *extra]
  end

  desc "Build the Tailwind stylesheet"
  task build: :environment do
    puts "Building #{OUTPUT} with Tailwind..."
    system(*tailwind_command("--minify"), exception: true)
  end

  desc "Watch and rebuild the Tailwind stylesheet"
  task watch: :environment do
    system(*tailwind_command("--watch"))
  end
end

if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance(["css:build"])
end
