# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    inertia_config layout: "inertia_admin"

    before_action :require_admin_access!

    private

    def require_admin_access!
      require_login
      return if performed?

      unless current_user.can_access_admin?
        redirect_to root_path, alert: t("mcweb.flash.admin_access_denied")
        return
      end

      unless current_user.permission?("admin.access")
        redirect_to root_path, alert: t("mcweb.flash.permission_denied")
      end
    end

    def require_admin_module!(module_key)
      return if current_user.admin_module_allowed?(module_key)

      redirect_to admin_root_path, alert: t("mcweb.flash.admin_module_denied")
    end
  end
end
