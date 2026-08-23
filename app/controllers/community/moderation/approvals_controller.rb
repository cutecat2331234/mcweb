# frozen_string_literal: true

module Community
  module Moderation
    class ApprovalsController < ApplicationController
      include PrivateNoStoreResponse

      before_action :require_login
      before_action :require_staff_moderator

      def index
        redirect_to staff_forum_approvals_path(page: params[:page])
      end

      private

      def require_staff_moderator
        return if Community::SectionModeration.staff_for_any_section?(current_user)

        redirect_to forum_latest_path, alert: t("mcweb.flash.cannot_moderate")
      end
    end
  end
end
