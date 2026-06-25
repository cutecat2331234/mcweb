# frozen_string_literal: true

module Community
  # XenForo-style "The Staff" page: members with admin/staff access.
  class StaffController < ApplicationController
    def index
      staff = User.where(status: :active)
        .where(id: AdminModuleGrant.select(:user_id))
        .includes(:user_badges)
        .order(:username)

      render inertia: "Community/Staff/Index", props: {
        staff: staff.map { |user| serialize_staff(user) }
      }
    end

    private

    def serialize_staff(user)
      modules = user.admin_module_grants.map(&:module_key).uniq.sort
      {
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        profile_url: forum_user_path(user.username),
        title: resolved_user_title(user),
        modules: modules.map { |key| t("mcweb.admin.modules.#{key}", default: key.humanize) },
        online: user.last_seen_at.present? && user.last_seen_at > 5.minutes.ago,
        last_seen_at: user.last_seen_at ? l(user.last_seen_at, format: :short) : nil
      }
    end
  end
end
