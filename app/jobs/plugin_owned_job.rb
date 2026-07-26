# frozen_string_literal: true

require "mcweb/plugins/job_runner"

class PluginOwnedJob < ApplicationJob
  queue_as :plugins

  def perform(run_public_id)
    Mcweb::Plugins::JobRunner.new.perform(run_public_id)
  end
end
