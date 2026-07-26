# frozen_string_literal: true

require "yaml"
require_relative "developer_mode"

module Mcweb
  module SidekiqCronSchedule
    Registration = Struct.new(:status, :job_count, keyword_init: true)

    class << self
      def automatic_registration_enabled?(
        settings: Mcweb::DeveloperMode.settings
      )
        !settings.enabled?
      end

      def configure_scheduler!(
        configuration:,
        settings: Mcweb::DeveloperMode.settings
      )
        return true if automatic_registration_enabled?(settings: settings)

        configuration.enabled = false
        configuration.cron_poll_interval = 0
        false
      end

      def register!(
        schedule_path:,
        settings: Mcweb::DeveloperMode.settings
      )
        unless automatic_registration_enabled?(settings: settings)
          return Registration.new(
            status: :disabled_by_developer_mode,
            job_count: 0
          ).freeze
        end

        unless File.exist?(schedule_path)
          return Registration.new(status: :missing, job_count: 0).freeze
        end

        schedule = YAML.load_file(schedule_path)
        yield schedule

        Registration.new(
          status: :registered,
          job_count: schedule.respond_to?(:size) ? schedule.size : 0
        ).freeze
      end
    end
  end
end
