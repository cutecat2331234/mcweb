# frozen_string_literal: true

module Identity
  class PermissionVersion
    class << self
      def bump_users!(user_ids)
        ids = Array(user_ids).filter_map { |value| Integer(value, exception: false) }
          .select(&:positive?)
          .uniq
        return 0 if ids.empty?

        User.where(id: ids).update_all(
          "permission_version = permission_version + 1, updated_at = CURRENT_TIMESTAMP"
        )
      end

      def bump_role_users!(role_id)
        bump_users!(UserRole.where(role_id: role_id).select(:user_id).pluck(:user_id))
      end

      def bump_group_users!(group_id)
        bump_users!(
          Community::GroupMembership
            .where(community_user_group_id: group_id)
            .select(:user_id)
            .pluck(:user_id)
        )
      end
    end
  end
end
