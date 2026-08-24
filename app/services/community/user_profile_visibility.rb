# frozen_string_literal: true

module Community
  # Keeps private account activity out of public community surfaces. The
  # permission is intentionally separate from moderation permissions: being
  # able to edit or warn a member does not automatically grant access to their
  # commerce, points, presence, or game-activity history.
  class UserProfileVisibility
    PRIVATE_ACTIVITY_PERMISSION = "identity.users.private_activity.read"

    PUBLIC_MEMBER_SORTS = %w[posts joined likes reviews].freeze
    PRIVATE_MEMBER_SORTS = %w[active online purchases].freeze

    def self.private_directory_visible?(viewer:)
      viewer&.persisted? && viewer.permission?(PRIVATE_ACTIVITY_PERMISSION)
    end

    def initialize(user:, viewer:)
      @user = user
      @viewer = viewer
    end

    def private_activity?
      return false unless @viewer && @user

      same_account? || self.class.private_directory_visible?(viewer: @viewer)
    end

    # Public profile activity is deliberately narrower than private activity.
    # A member can opt in to the summary fields serialized by
    # UserProfileActivitySerializer without exposing private-only account
    # details such as membership expiry, profile views, or internal roles.
    def activity_summary?
      private_activity? || public_activity_opt_in?
    end

    def owner?
      same_account?
    end

    def account_type?
      same_account? || persisted_viewer_permission?("system.settings.manage")
    end

    def role_assignments?
      same_account? || persisted_viewer_permission?("identity.permissions.explain")
    end

    def game_permission_groups?
      same_account? || persisted_viewer_permission?("minecraft.players.view")
    end

    private

    def persisted_user?
      @user&.persisted?
    end

    def public_activity_opt_in?
      persisted_user? && @user.active? && @user.forum_profile_activity_public?
    end

    def same_account?
      @viewer&.persisted? && @user&.persisted? && @viewer.id == @user.id
    end

    def persisted_viewer_permission?(permission)
      @viewer&.persisted? && @viewer.permission?(permission)
    end
  end
end
