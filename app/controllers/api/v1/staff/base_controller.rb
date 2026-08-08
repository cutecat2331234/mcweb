# frozen_string_literal: true

module Api
  module V1
    module Staff
      class BaseController < Api::V1::BaseController
        skip_before_action :require_read_scope!
        before_action :require_bound_user!
        before_action :require_staff_read_scope!
        before_action :require_staff_workspace_access!
        after_action :disable_staff_api_caching

        private

        def staff_moderation_policy
          @staff_moderation_policy ||= Community::ModerationWorkbench::Policy.new(api_user)
        end

        def require_staff_read_scope!
          require_staff_scope!("staff.moderation.read")
        end

        def require_staff_scope!(scope)
          return true if current_api_key&.allows?(scope)

          render_error("insufficient_scope", status: :forbidden, extra: { required: scope })
          false
        end

        def require_staff_workspace_access!
          return if staff_moderation_policy.accessible?

          render_error("staff_workspace_forbidden", status: :forbidden)
        end

        def disable_staff_api_caching
          response.cache_control[:no_store] = true
          response.cache_control[:private] = true
        end
      end
    end
  end
end
