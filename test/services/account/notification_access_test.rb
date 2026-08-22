# frozen_string_literal: true

require "test_helper"

module Account
  class NotificationAccessTest < ActiveSupport::TestCase
    class RejectAllPolicy
      def initialize(user:, notifications:)
        @user = user
        @notifications = notifications
      end

      def visible?(_notification)
        false
      end
    end

    class AllowAllPolicy
      def initialize(user:, notifications:)
        @user = user
        @notifications = notifications
      end

      def visible?(_notification)
        true
      end
    end

    test "only forum notifications interpret forum metadata keys" do
      user = create_user
      forum_notification = user.notifications.create!(
        notification_type: "forum.topic_reply",
        title: "Forum notification",
        metadata: { topic_id: "missing-topic" }
      )
      pvp_notification = user.notifications.create!(
        notification_type: "pvp.test_completed",
        title: "PVP notification",
        metadata: { topic_id: "downstream-resource-id" }
      )
      access = NotificationAccess.new(
        user:,
        notifications: [ forum_notification, pvp_notification ]
      )

      assert_not access.visible?(forum_notification)
      assert access.visible?(pvp_notification)
    end

    test "rejects notifications owned by another account" do
      user = create_user
      notification = create_user.notifications.create!(
        notification_type: "system.notice",
        title: "Another account"
      )

      assert_not NotificationAccess.visible?(notification:, user:)
    end

    test "allows downstream domains to register a visibility policy" do
      original_registry = NotificationAccess.send(:registry)
      user = create_user
      notification = user.notifications.create!(
        notification_type: "chat.safety.sanction",
        title: "Safety notification"
      )

      NotificationAccess.register(prefixes: [ "chat.safety.", "chat." ], policy: RejectAllPolicy)

      assert_not NotificationAccess.visible?(notification:, user:)

      NotificationAccess.register(prefixes: [ "chat.safety.", "chat." ], policy: AllowAllPolicy)
      assert NotificationAccess.visible?(notification:, user:)

      error = assert_raises(ArgumentError) do
        NotificationAccess.register(prefixes: [ "forum." ], policy: AllowAllPolicy)
      end
      assert_includes error.message, "built in"
    ensure
      NotificationAccess.instance_variable_set(:@registry, original_registry)
    end
  end
end
