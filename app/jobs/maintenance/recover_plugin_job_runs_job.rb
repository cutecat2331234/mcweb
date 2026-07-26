# frozen_string_literal: true

require "mcweb/plugins/job_recovery"

module Maintenance
  class RecoverPluginJobRunsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Mcweb::Plugins::JobRecovery.call
    end
  end
end
