# frozen_string_literal: true

module Community
  # Recipient-side "who can message me" control, complementing per-user UserBlock.
  # Staff can always initiate (so moderation contact is never blocked).
  module PmPolicy
    POLICIES = %w[everyone following_only staff_only].freeze

    module_function

    def accepts?(recipient:, sender:)
      return true if sender.permission?("forum.topics.lock") || sender.permission?("admin.access")

      case recipient.forum_pm_policy
      when "following_only" then Community::UserFollow.exists?(follower: recipient, followed: sender)
      when "staff_only" then false
      else true
      end
    end
  end
end
