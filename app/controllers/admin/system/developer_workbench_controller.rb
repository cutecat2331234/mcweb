# frozen_string_literal: true

module Admin
  module System
    class DeveloperWorkbenchController < BaseController
      prepend_before_action :require_developer_mode!
      before_action -> { require_permission("system.settings.manage") }

      def show
        render inertia: "Admin/System/DeveloperWorkbench/Show", props:
          Operations::DeveloperWorkbenchSnapshot.call.merge(
            settingsUrl: admin_system_settings_path,
            jobsUrl: admin_system_jobs_path
          )
      end

      private

      def require_developer_mode!
        head :not_found unless Mcweb::DeveloperMode.enabled?
      end
    end
  end
end
