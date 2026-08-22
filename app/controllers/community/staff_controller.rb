# frozen_string_literal: true

module Community
  # XenForo-style "The Staff" page: members with admin/staff access.
  class StaffController < ApplicationController
    include ViewerScopedNoStoreResponse

    def index
      staff = User.where(status: :active)
        .where(id: AdminModuleGrant.select(:user_id))
        .includes(:user_badges)
        .order(:username)
      visible_post_counts = Community::ForumAccess.listed_post_scope(
        relation: Community::Post.where(user_id: staff.reorder(nil).select(:id)),
        user: current_user
      ).group(:user_id).count

      render inertia: "Community/Staff/Index", props: {
        staff: staff.map do |user|
          serialize_staff(user, posts_count: visible_post_counts[user.id].to_i)
        end
      }
    end

    private

    def serialize_staff(user, posts_count:)
      visibility = Community::UserProfileVisibility.new(user: user, viewer: current_user)
      modules = user.admin_module_grants.map(&:module_key).uniq.sort
      payload = {
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        profile_url: forum_user_path(user.username),
        title: resolved_user_title(user, posts_count: posts_count),
        modules: visibility.role_assignments? ? modules.map { |key| t("mcweb.admin.modules.#{key}", default: key.humanize) } : []
      }
      return payload unless visibility.private_activity?

      payload.merge(
        online: user.last_seen_at.present? && user.last_seen_at > 5.minutes.ago,
        last_seen_at: user.last_seen_at ? l(user.last_seen_at, format: :short) : nil
      )
    end
  end
end
