# frozen_string_literal: true

module Community
  # Who may post/comment on profile walls. Mirrors the trust-level gating used
  # elsewhere (e.g. TrustLevel.can_send_pm?), plus respects the wall owner's block list.
  module ProfileWallPolicy
    module_function

    def enabled?
      SiteSetting.get("forum.profile_posts_enabled", "true") == "true"
    end

    def min_trust_level
      SiteSetting.get("forum.min_trust_level_profile_post", "1").to_i
    end

    def can_post?(author:, profile_user:)
      return false unless author && profile_user
      return false unless enabled?
      return false if Community::UserBlock.exists?(blocker: profile_user, blocked: author)
      return true if author.permission?("forum.topics.lock") || author.permission?("admin.access")

      Community::TrustLevel.level_for(author) >= min_trust_level
    end

    def can_comment?(author:, profile_post:)
      return false unless profile_post

      can_post?(author: author, profile_user: profile_post.profile_user)
    end
  end
end
