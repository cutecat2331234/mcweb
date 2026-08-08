# frozen_string_literal: true

module Staff
  class BaseController < ApplicationController
    before_action :require_login
    before_action :require_staff_workspace_access!
    after_action :disable_staff_workspace_caching

    private

    def staff_moderation_policy
      @staff_moderation_policy ||= Community::ModerationWorkbench::Policy.new(current_user)
    end

    def require_staff_workspace_access!
      return if staff_moderation_policy.accessible?

      redirect_to forum_sections_path, alert: t("mcweb.flash.permission_denied")
    end

    def disable_staff_workspace_caching
      response.cache_control[:no_store] = true
      response.cache_control[:private] = true
    end
  end
end
