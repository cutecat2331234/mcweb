# frozen_string_literal: true

module Admin
  module System
    class JobsController < BaseController
      before_action -> { require_permission("system.jobs.read") }

      def index
        developer_mode_enabled = Mcweb::DeveloperMode.enabled?
        render inertia: "Admin/System/Jobs/Index", props: {
          dashboardUrl: "/jobs",
          developerMode: {
            enabled: developer_mode_enabled,
            profile: developer_mode_enabled ?
              Mcweb::DeveloperMode.profile.to_s :
              nil
          },
          automaticRegistration:
            Mcweb::SidekiqCronSchedule.automatic_registration_enabled?
        }
      end
    end
  end
end
