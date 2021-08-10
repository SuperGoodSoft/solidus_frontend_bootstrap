# frozen_string_literal: true

require "solidus_core"
require "solidus_support"

module SolidusFrontendBootstrap
  class Engine < Rails::Engine
    include SolidusSupport::EngineExtensions

    isolate_namespace ::Spree

    engine_name "solidus_frontend_bootstrap"

    # use rspec for tests
    config.generators do |g|
      g.test_framework :rspec
    end
    # config.to_prepare do
    #   # Load application's model / class decorators
    #   Dir.glob(File.join(File.dirname(__FILE__), "../../app/**/*_decorator*.rb")) do |c|
    #     Rails.configuration.cache_classes ? require(c) : load(c)
    #   end
    # end
  end
end
