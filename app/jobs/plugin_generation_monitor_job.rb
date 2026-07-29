# frozen_string_literal: true

require "mcweb/plugins/generation_coordinator"

class PluginGenerationMonitorJob < ApplicationJob
  queue_as :plugins

  def perform(generation_id)
    Mcweb::Plugins::GenerationCoordinator.new.finalize!(generation_id)
  end
end
