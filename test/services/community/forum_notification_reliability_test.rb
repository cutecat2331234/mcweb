# frozen_string_literal: true

require "test_helper"

class Community::ForumNotificationReliabilityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    suffix = SecureRandom.hex(4)
    @author = create_user(username: "mention_author_#{suffix}")
    @recipient = create_user(username: "mention_target_#{suffix}")
    category = Community::Category.create!(
      name: "Notification reliability",
      slug: "notification-reliability-#{suffix}"
    )
    @section = Community::Section.create!(
      category: category,
      name: "Notification reliability",
      slug: "notification-reliability-section-#{suffix}",
      position: 0
    )

    @recipient.update!(forum_digest_frequency: "none")
    NotificationPreference.set!(
      @recipient,
      channel: "in_app",
      notification_type: "forum.mention",
      enabled: true
    )
    NotificationPreference.set!(
      @recipient,
      channel: "email",
      notification_type: "forum.mention",
      enabled: true
    )
  end

  test "creating a topic dispatches one mention notification and one email" do
    result = nil

    assert_difference mention_notifications, 1 do
      assert_enqueued_jobs 1, only: MailDeliveryJob do
        result = Community::CreateTopic.call(
          user: @author,
          section: @section,
          title: "Mention reliability",
          body: "Hello @#{@recipient.username}"
        )
      end
    end

    assert result.success?
  end

  test "an ignored author cannot notify or email the recipient through a mention" do
    Community::SetUserIgnore.call(
      ignorer: @recipient,
      ignored_username: @author.username,
      desired_state: true
    )
    topic, post = create_topic_and_post(body: "Hello @#{@recipient.username}")

    assert_no_difference mention_notifications do
      assert_no_enqueued_jobs only: MailDeliveryJob do
        Community::ProcessMentions.call(
          body: post.body,
          author: @author,
          post: post,
          topic: topic
        )
      end
    end
  end

  test "a blocked author cannot notify or email the recipient through a mention" do
    Community::UserBlock.create!(blocker: @recipient, blocked: @author)
    topic, post = create_topic_and_post(body: "Hello @#{@recipient.username}")

    assert_no_difference mention_notifications do
      assert_no_enqueued_jobs only: MailDeliveryJob do
        Community::ProcessMentions.call(
          body: post.body,
          author: @author,
          post: post,
          topic: topic
        )
      end
    end
  end

  test "mention email remains independent from the in-app preference" do
    NotificationPreference.set!(
      @recipient,
      channel: "in_app",
      notification_type: "forum.mention",
      enabled: false
    )
    topic, post = create_topic_and_post(body: "Hello @#{@recipient.username}")

    assert_no_difference mention_notifications do
      assert_enqueued_jobs 1, only: MailDeliveryJob do
        Community::ProcessMentions.call(
          body: post.body,
          author: @author,
          post: post,
          topic: topic
        )
      end
    end
  end

  test "watch email remains independent from the in-app topic reply preference" do
    topic, post = create_topic_and_post(body: "A watched reply")
    Community::Subscription.create!(
      user: @recipient,
      subscribable: topic,
      notification_level: "watching"
    )
    NotificationPreference.set!(
      @recipient,
      channel: "in_app",
      notification_type: "forum.topic_reply",
      enabled: false
    )
    NotificationPreference.set!(
      @recipient,
      channel: "email",
      notification_type: "forum.topic_reply",
      enabled: true
    )

    count = -> { Notification.where(user: @recipient, notification_type: "forum.topic_reply").count }
    assert_no_difference count do
      assert_enqueued_jobs 1, only: MailDeliveryJob do
        Community::NotifyTopicReply.call(post: post)
      end
    end
  end

  test "rolling back a mention transaction leaves no notification or email job" do
    topic, post = create_topic_and_post(body: "Hello @#{@recipient.username}")

    assert_no_difference mention_notifications do
      assert_no_enqueued_jobs only: MailDeliveryJob do
        Notification.transaction(requires_new: true) do
          Community::ProcessMentions.call(
            body: post.body,
            author: @author,
            post: post,
            topic: topic
          )
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  test "rolling back a watched reply leaves no notification or email job" do
    topic, post = create_topic_and_post(body: "A rolled back watched reply")
    Community::Subscription.create!(
      user: @recipient,
      subscribable: topic,
      notification_level: "watching"
    )
    count = -> { Notification.where(user: @recipient, notification_type: "forum.topic_reply").count }

    assert_no_difference count do
      assert_no_enqueued_jobs only: MailDeliveryJob do
        Notification.transaction(requires_new: true) do
          Community::NotifyTopicReply.call(post: post)
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  private

  def mention_notifications
    -> { Notification.where(user: @recipient, notification_type: "forum.mention").count }
  end

  def create_topic_and_post(body:)
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Mention service",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    post = Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: 1,
      body: body,
      status: "published"
    )
    [ topic, post ]
  end
end
