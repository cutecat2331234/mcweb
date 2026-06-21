# frozen_string_literal: true

module Admin
  module System
    class ApplicationsController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      def index
        catalog = Mcweb::ApplicationRegistry.admin_catalog

        render inertia: "Admin/System/Applications/Index", props: {
          title: t("mcweb.admin.system.applications.title"),
          platform: catalog[:platform],
          applications: catalog[:applications],
          extensions: catalog[:extensions],
          freelyExtensible: Mcweb::ApplicationRegistry.freely_extensible?,
          featureFlagsUrl: admin_system_feature_toggles_path
        }
      end
    end
  end
end
