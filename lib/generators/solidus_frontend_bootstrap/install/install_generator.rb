# frozen_string_literal: true

module SolidusFrontendBootstrap
  module Generators
    class InstallGenerator < Rails::Generators::Base

      source_root File.expand_path('templates', __dir__)

      def add_javascripts
        append_file 'vendor/assets/javascripts/spree/frontend/all.js', "//= require spree/frontend/solidus_frontend_bootstrap\n"
      end

      def add_stylesheets
        inject_into_file 'vendor/assets/stylesheets/spree/frontend/all.css', " *= require spree/frontend/solidus_frontend_bootstrap\n", before: %r{\*/}, verbose: true # rubocop:disable Layout/LineLength
      end

    end
  end
end
