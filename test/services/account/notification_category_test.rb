# frozen_string_literal: true

require "test_helper"

module Account
  class NotificationCategoryTest < ActiveSupport::TestCase
    test "classifies built-in and unknown notification types without treating unknown domains as forum" do
      assert_equal "forum", NotificationCategory.for("forum.mention")
      assert_equal "commerce", NotificationCategory.for("commerce.order_created")
      assert_equal "system", NotificationCategory.for("system.notice")
      assert_equal "system", NotificationCategory.for("chat.safety.appeal_accepted")
      assert_equal "system", NotificationCategory.for("pvp.test_completed")
      assert_equal "system", NotificationCategory.for("plugin.release_ready")
    end

    test "applies mutually exclusive forum commerce and system scopes" do
      user = create_user
      types = %w[
        forum.mention
        commerce.order_created
        system.notice
        chat.safety.appeal_accepted
        pvp.test_completed
        plugin.release_ready
      ]
      types.each { |type| user.notifications.create!(notification_type: type, title: type) }

      assert_equal [ "forum.mention" ], types_for(user, "forum")
      assert_equal [ "commerce.order_created" ], types_for(user, "commerce")
      assert_equal %w[
        chat.safety.appeal_accepted
        plugin.release_ready
        pvp.test_completed
        system.notice
      ], types_for(user, "system")
    end

    test "allows downstream domains to register categories without changing CE configuration" do
      original_registry = NotificationCategory.send(:registry)

      NotificationCategory.register("chat", prefixes: [ "chat.safety.", "chat." ])

      assert_includes NotificationCategory.categories, "chat"
      assert_equal "chat", NotificationCategory.for("chat.safety.appeal_accepted")
      assert_equal "chat", NotificationCategory.for("chat.message_received")
      assert_equal "system", NotificationCategory.for("pvp.test_completed")

      user = create_user
      %w[chat.safety.appeal_accepted chat.message_received pvp.test_completed].each do |type|
        user.notifications.create!(notification_type: type, title: type)
      end
      assert_equal %w[chat.message_received chat.safety.appeal_accepted], types_for(user, "chat")
      assert_equal [ "pvp.test_completed" ], types_for(user, "system")

      error = assert_raises(ArgumentError) do
        NotificationCategory.register("safety", prefixes: [ "chat.safety." ])
      end
      assert_includes error.message, "overlap"
    ensure
      NotificationCategory.instance_variable_set(:@registry, original_registry)
    end

    private

    def types_for(user, category)
      NotificationCategory.apply(user.notifications, category).pluck(:notification_type).sort
    end
  end
end
