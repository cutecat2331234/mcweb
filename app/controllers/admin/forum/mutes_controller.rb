# frozen_string_literal: true

module Admin
  module Forum
    class MutesController < BaseController
      before_action -> { require_permission("forum.users.mute") }

      def create
        user = User.find_by!(public_id: params[:user_id])
        section = params[:section_id].present? ? Community::Section.find_by(slug: params[:section_id]) : nil

        result = Community::CreateMute.call(
          actor: current_user,
          user: user,
          section: section,
          reason: params[:reason],
          expires_at: parse_expires(params[:expires_at])
        )

        if result.success?
          redirect_to admin_user_path(user), notice: t("mcweb.flash.user_muted")
        else
          redirect_to admin_user_path(user), alert: service_error_message(result)
        end
      end

      def destroy
        mute = Community::Mute.find(params[:id])
        user = mute.user
        result = Community::RemoveMute.call(actor: current_user, mute: mute)

        if result.success?
          redirect_to admin_user_path(user), notice: t("mcweb.flash.user_unmuted")
        else
          redirect_to admin_user_path(user), alert: service_error_message(result)
        end
      end

      private

      def parse_expires(value)
        return nil if value.blank?

        Time.zone.parse(value)
      rescue ArgumentError
        nil
      end
    end
  end
end
