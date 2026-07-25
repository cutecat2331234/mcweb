# frozen_string_literal: true

require "test_helper"

module Community
  class DeliverWebPushPrivacyTest < ActiveSupport::TestCase
    setup do
      suffix = SecureRandom.hex(4)
      category = Community::Category.create!(
        name: "Web push privacy",
        slug: "web-push-privacy-#{suffix}"
      )
      @section = Community::Section.create!(
        category: category,
        name: "Web push privacy",
        slug: "web-push-privacy-section-#{suffix}",
        position: 0
      )
      @user = create_user
      @author = create_user
      @topic = Community::Topic.create!(
        section: @section,
        user: @author,
        title: "Web push privacy topic",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      @post = Community::Post.create!(
        topic: @topic,
        user: @author,
        floor_number: 1,
        body: "Web push private body",
        status: "published"
      )
      Community::PushSubscription.create!(
        user: @user,
        endpoint: "https://push.example.test/#{suffix}",
        p256dh_key: "p256dh-#{suffix}",
        auth_key: "auth-#{suffix}"
      )
      NotificationPreference.set!(
        @user,
        channel: "web_push",
        notification_type: "forum.mention",
        enabled: true
      )
    end

    test "job and service recheck section permission before web push" do
      notification = create_post_notification
      @section.update!(permissions: { "view" => [ "forum.private.section" ] })

      assert_push_blocked(notification)
    end

    test "job and service recheck post soft deletion before web push" do
      notification = create_post_notification
      @post.soft_delete!

      assert_push_blocked(notification)
    end

    test "job and service reject banned and deleted recipients" do
      NotificationPreference.set!(
        @user,
        channel: "web_push",
        notification_type: "forum.new_follower",
        enabled: true
      )
      notification = Notification.create!(
        user: @user,
        notification_type: "forum.new_follower",
        title: "Account status push",
        body: "Must not be sent"
      )

      %w[banned deleted].each do |status|
        @user.update!(status: status)
        assert_push_blocked(notification)
        @user.update!(status: "active")
      end
    end

    private

    def create_post_notification
      Notification.create!(
        user: @user,
        notification_type: "forum.mention",
        title: "Web push private title",
        body: @post.body,
        metadata: {
          topic_id: @topic.public_id,
          post_id: @post.id,
          path: "/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"
        }
      )
    end

    def assert_push_blocked(notification)
      push_calls = 0
      sender = lambda do |**|
        push_calls += 1
      end
      with_singleton_method(WebPush, :payload_send, sender) do
        result = Community::DeliverWebPush.call(notification: notification)
        assert_predicate result, :success?
        assert result.value[:skipped]
      end
      assert_equal 0, push_calls

      service_calls = 0
      replacement = lambda do |**|
        service_calls += 1
      end
      with_singleton_method(Community::DeliverWebPush, :call, replacement) do
        Community::DeliverWebPushJob.perform_now(notification.id)
      end
      assert_equal 0, service_calls
    end

    def with_singleton_method(object, method_name, replacement)
      original = object.method(method_name)
      object.define_singleton_method(method_name, replacement)
      yield
    ensure
      object.define_singleton_method(method_name, original)
    end
  end
end
