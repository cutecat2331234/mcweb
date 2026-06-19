# frozen_string_literal: true

module Admin
  module System
    class FeatureTogglesController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      def show
        render inertia: "Admin/System/FeatureToggles/Show", props: {
          features: FeatureFlags.admin_props
        }
      end

      def update
        result = FeatureFlags.update_from_params!(params.fetch(:features, {}))
        unless result.success?
          redirect_to admin_system_feature_toggles_path, alert: result.error
          return
        end

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.feature_toggles_updated",
          metadata: { features: FeatureFlags.frontend_hash }
        )

        redirect_to admin_system_feature_toggles_path, notice: t("mcweb.flash.feature_toggles_saved")
      end
    end
  end
end
