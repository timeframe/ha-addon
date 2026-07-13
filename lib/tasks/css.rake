# frozen_string_literal: true

# Builds ha-addon's Tailwind bundle (the app's only stylesheet). Hooks into
# assets:precompile.
namespace :css do
  def tailwind_command(*extra)
    require "tailwindcss/ruby"

    input = Rails.root.join("app/assets/stylesheets/application.tailwind.css")
    output = Rails.root.join("app/assets/builds/application_tailwind.css")
    [Tailwindcss::Ruby.executable.to_s, "--input", input.to_s, "--output", output.to_s, *extra]
  end

  desc "Build the Tailwind stylesheet"
  task build: :environment do
    puts "Building application_tailwind.css with Tailwind..."
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
