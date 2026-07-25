# frozen_string_literal: true

require "test_helper"

module Community
  class NotificationAccessTest < ActiveSupport::TestCase
    include ActionMailer::TestHelper

    setup do
      suffix = SecureRandom.hex(4)
      category = Community::Category.create!(
        name: "Notification access",
        slug: "notification-access-#{suffix}"
      )
      @section = Community::Section.create!(
        category: category,
        name: "Notification access",
        slug: "notification-access-section-#{suffix}",
        position: 0
      )
      @author = create_user
      @recipient = create_user
      @topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: @section,
        user: @author,
        title: "Notification access topic",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
    end

    test "banned and deleted recipients cannot consume or receive forum resource notifications" do
      %w[banned deleted].each do |status|
        recipient = create_user
        notification = recipient.notifications.create!(
          notification_type: "forum.section_topic",
          title: "Restricted account notification",
          body: @topic.title,
          metadata: { topic_id: @topic.public_id }
        )
        recipient.update!(
          forum_digest_frequency: "daily",
          forum_digest_last_sent_at: 2.days.ago
        )
        status == "banned" ? recipient.ban! : recipient.soft_delete!

        assert_not Community::NotificationAccess.visible?(
          notification: notification,
          user: recipient
        )
        assert_no_enqueued_jobs only: MailDeliveryJob do
          result = Community::SendForumDigest.call(user: recipient)
          assert_predicate result, :success?
          assert result.value[:skipped]
        end
        assert_no_emails do
          Community::ForumMailer
            .section_topic(recipient.id, @topic.public_id)
            .deliver_now
        end
      end
    end

    test "private message mail requires a kept message in the recipient conversation" do
      conversation = create_conversation(@recipient, @author)
      message = Community::Message.create!(
        conversation: conversation,
        user: @author,
        body: "Private mail secret"
      )

      assert_emails 1 do
        Community::ForumMailer
          .private_message(@recipient.id, conversation.id, message.id)
          .deliver_now
      end

      other_conversation = create_conversation(@recipient, @author)
      assert_no_emails do
        Community::ForumMailer
          .private_message(@recipient.id, other_conversation.id, message.id)
          .deliver_now
      end

      message.soft_delete!
      assert_no_emails do
        Community::ForumMailer
          .private_message(@recipient.id, conversation.id, message.id)
          .deliver_now
      end

      message.restore!
      conversation.participants.find_by!(user: @recipient).destroy!
      assert_no_emails do
        Community::ForumMailer
          .private_message(@recipient.id, conversation.id, message.id)
          .deliver_now
      end
    end

    test "conversation notifications are removed from both digest stages after membership is revoked" do
      conversation = create_conversation(@recipient, @author)
      message = Community::Message.create!(
        conversation: conversation,
        user: @author,
        body: "Revoked conversation message"
      )
      notification = @recipient.notifications.create!(
        notification_type: "forum.private_message",
        title: "Revoked conversation secret",
        body: "Revoked conversation body",
        metadata: {
          conversation_id: conversation.id,
          message_id: message.id,
          path: "/app/forum/conversations/#{conversation.id}"
        }
      )
      conversation.participants.find_by!(user: @recipient).destroy!

      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )

      @recipient.update!(
        forum_digest_frequency: "daily",
        forum_digest_last_sent_at: 2.days.ago
      )
      assert_no_enqueued_jobs only: MailDeliveryJob do
        result = Community::SendForumDigest.call(user: @recipient)
        assert_predicate result, :success?
        assert result.value[:skipped]
      end
      assert_not notification.reload.read?

      assert_no_emails do
        Community::ForumMailer.digest(@recipient.id, [ notification.id ]).deliver_now
      end
    end

    test "private message notifications fail closed for deleted or legacy messages" do
      conversation = create_conversation(@recipient, @author)
      message = Community::Message.create!(
        conversation: conversation,
        user: @author,
        body: "Ephemeral private notification"
      )
      notification = @recipient.notifications.create!(
        notification_type: "forum.private_message",
        title: "Private notification",
        body: message.body,
        metadata: {
          conversation_id: conversation.id,
          message_id: message.id
        }
      )
      legacy = @recipient.notifications.create!(
        notification_type: "forum.private_message",
        title: "Legacy private notification",
        body: "Legacy private body",
        metadata: { conversation_id: conversation.id }
      )

      assert Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
      assert_not Community::NotificationAccess.visible?(
        notification: legacy,
        user: @recipient
      )

      message.soft_delete!
      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
    end

    test "post notifications are hidden when their referenced post becomes unavailable" do
      post = Community::Post.create!(
        topic: @topic,
        user: @author,
        floor_number: 1,
        body: "Post notification secret",
        status: "published"
      )
      notification = @recipient.notifications.create!(
        notification_type: "forum.mention",
        title: "Mention notification",
        body: post.body,
        metadata: {
          topic_id: @topic.public_id,
          post_id: post.id
        }
      )

      assert Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )

      post.soft_delete!
      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
      assert_no_emails do
        Community::ForumMailer
          .mention(@recipient.id, @topic.public_id, post.id)
          .deliver_now
      end
    end

    test "section permission changes are rechecked by notification mail and both digest stages" do
      post = Community::Post.create!(
        topic: @topic,
        user: @author,
        floor_number: 1,
        body: "Permission-change mail secret",
        status: "published"
      )
      notification = @recipient.notifications.create!(
        notification_type: "forum.mention",
        title: "Permission-change notification secret",
        body: post.body,
        metadata: {
          topic_id: @topic.public_id,
          post_id: post.id
        }
      )
      assert Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )

      @section.update!(permissions: { "view" => [ "forum.private.section" ] })

      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
      assert_no_emails do
        Community::ForumMailer
          .mention(@recipient.id, @topic.public_id, post.id)
          .deliver_now
      end

      @recipient.update!(
        forum_digest_frequency: "daily",
        forum_digest_last_sent_at: 2.days.ago
      )
      assert_no_enqueued_jobs only: MailDeliveryJob do
        result = Community::SendForumDigest.call(user: @recipient)
        assert result.value[:skipped]
      end
      assert_not notification.reload.read?
      assert_no_emails do
        Community::ForumMailer.digest(
          @recipient.id,
          [ notification.id ]
        ).deliver_now
      end
    end

    test "unlisted topics do not remain exposed on notification surfaces" do
      notification = @recipient.notifications.create!(
        notification_type: "forum.followed_topic",
        title: "Unlisted topic secret",
        body: @topic.title,
        metadata: { topic_id: @topic.public_id }
      )
      assert Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )

      @topic.update!(unlisted: true)

      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
      assert_no_emails do
        Community::ForumMailer
          .followed_topic(@recipient.id, @topic.public_id)
          .deliver_now
      end
    end

    test "rejection notification survives moderation state but not soft deletion" do
      post = Community::Post.create!(
        topic: @topic,
        user: @recipient,
        floor_number: 1,
        body: "Rejected post secret",
        status: "hidden"
      )
      notification = @recipient.notifications.create!(
        notification_type: "forum.post_rejected",
        title: "Post rejected",
        body: "Private rejection reason",
        metadata: {
          topic_id: @topic.public_id,
          post_id: post.id
        }
      )

      assert Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
      post.soft_delete!
      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
    end

    test "saved search notification rechecks every captured topic at both digest stages" do
      other_topic = Community::Topic.create!(
        section: @section,
        user: @author,
        title: "Saved search topic to remove",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      search = Community::SavedSearch.create!(
        user: @recipient,
        name: "Privacy search",
        query: "privacy",
        filters: {}
      )
      notification = @recipient.notifications.create!(
        notification_type: "forum.saved_search_match",
        title: "Saved search results",
        body: "#{@topic.title}, #{other_topic.title}",
        metadata: {
          search_id: search.id,
          topic_ids: [ @topic.public_id, other_topic.public_id ]
        }
      )
      legacy = @recipient.notifications.create!(
        notification_type: "forum.saved_search_match",
        title: "Legacy saved search",
        body: "Legacy captured titles",
        metadata: { search_id: search.id }
      )
      assert Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
      assert_not Community::NotificationAccess.visible?(
        notification: legacy,
        user: @recipient
      )

      other_topic.soft_delete!
      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )

      @recipient.update!(
        forum_digest_frequency: "daily",
        forum_digest_last_sent_at: 2.days.ago
      )
      assert_no_enqueued_jobs only: MailDeliveryJob do
        result = Community::SendForumDigest.call(user: @recipient)
        assert result.value[:skipped]
      end
      assert_no_emails do
        Community::ForumMailer.digest(
          @recipient.id,
          [ notification.id ]
        ).deliver_now
      end
    end

    test "profile comment notifications fail closed after comment deletion" do
      profile_post = Community::ProfilePost.create!(
        profile_user: @recipient,
        author: @author,
        body: "Profile post",
        status: "published"
      )
      comment = Community::ProfilePostComment.create!(
        profile_post: profile_post,
        author: @author,
        body: "Profile comment secret",
        status: "published"
      )
      notification = @recipient.notifications.create!(
        notification_type: "forum.profile_post_comment",
        title: "Profile comment",
        body: comment.body,
        metadata: {
          profile_post_id: profile_post.id,
          profile_post_comment_id: comment.id
        }
      )
      assert Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )

      comment.soft_delete!
      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
    end

    test "bookmark mail does not downgrade a deleted post bookmark to its topic" do
      post = Community::Post.create!(
        topic: @topic,
        user: @author,
        floor_number: 1,
        body: "Deleted bookmark post",
        status: "published"
      )
      bookmark = Community::Bookmark.create!(
        user: @recipient,
        topic: @topic,
        post: post,
        remind_at: 1.hour.ago
      )
      notification = @recipient.notifications.create!(
        notification_type: "forum.bookmark_reminder",
        title: "Deleted bookmark",
        body: "Private bookmark note",
        metadata: { bookmark_id: bookmark.id }
      )
      post.soft_delete!

      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
      assert_no_emails do
        Community::ForumMailer
          .bookmark_reminder(@recipient.id, bookmark.id)
          .deliver_now
      end
    end

    test "post mail rejects mismatched topic and post identifiers" do
      other_topic = Community::Topic.create!(
        section: @section,
        user: @author,
        title: "Other topic",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      post = Community::Post.create!(
        topic: @topic,
        user: @author,
        floor_number: 1,
        body: "Mismatched mail secret",
        status: "published"
      )

      assert_no_emails do
        Community::ForumMailer
          .mention(@recipient.id, other_topic.public_id, post.id)
          .deliver_now
      end
    end

    test "tag notifications only capture tags still usable and watched by each recipient" do
      public_tag = create_tag("Public watched tag")
      staff_tag = create_tag("Staff secret tag", staff_only: true)
      @topic.tags << public_tag << staff_tag
      subscribe(@recipient, public_tag)
      subscribe(@recipient, staff_tag)
      enable_tag_notifications(@recipient)
      stale_staff_subscriber = create_user
      subscribe(stale_staff_subscriber, staff_tag)
      enable_tag_notifications(stale_staff_subscriber)

      assert_enqueued_jobs 1, only: MailDeliveryJob do
        Community::NotifyTagTopic.call(topic: @topic, tags: [ public_tag, staff_tag ])
      end

      notification = @recipient.notifications.find_by!(notification_type: "forum.tag_topic")
      assert_includes notification.body, public_tag.name
      assert_not_includes notification.body, staff_tag.name
      assert_equal [ public_tag.id ], notification.metadata["tag_ids"]
      assert_nil stale_staff_subscriber.notifications.find_by(notification_type: "forum.tag_topic")
    end

    test "staff tag notifications are hidden and not delivered after permission is revoked" do
      staff_tag = create_tag("Permission revoked tag", staff_only: true)
      @topic.tags << staff_tag
      subscribe(@recipient, staff_tag)
      enable_tag_notifications(@recipient)
      grant_permission(@recipient, "forum.tags.manage")

      Community::NotifyTagTopic.call(topic: @topic, tags: [ staff_tag ])
      notification = @recipient.notifications.find_by!(notification_type: "forum.tag_topic")
      assert Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )

      @recipient.user_roles.delete_all
      @recipient.roles.reset
      assert_not @recipient.permission?("forum.tags.manage")
      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )

      @recipient.update!(
        forum_digest_frequency: "daily",
        forum_digest_last_sent_at: 2.days.ago
      )
      clear_enqueued_jobs
      assert_no_enqueued_jobs only: MailDeliveryJob do
        result = Community::SendForumDigest.call(user: @recipient)
        assert result.value[:skipped]
      end

      assert_no_emails do
        Community::ForumMailer
          .tag_topic(@recipient.id, @topic.public_id, [ staff_tag.id ])
          .deliver_now
        Community::ForumMailer.digest(@recipient.id, [ notification.id ]).deliver_now
      end
    end

    test "unsubscribing invalidates existing tag notifications and queued mail" do
      tag = create_tag("Unsubscribed tag")
      @topic.tags << tag
      subscription = subscribe(@recipient, tag)
      enable_tag_notifications(@recipient)
      Community::NotifyTagTopic.call(topic: @topic, tags: [ tag ])
      notification = @recipient.notifications.find_by!(notification_type: "forum.tag_topic")
      legacy_notification = @recipient.notifications.create!(
        notification_type: "forum.tag_topic",
        title: "Legacy tag notification",
        body: "Legacy leaked name",
        metadata: { topic_id: @topic.public_id }
      )
      assert_not Community::NotificationAccess.visible?(
        notification: legacy_notification,
        user: @recipient
      )

      subscription.destroy!

      assert_not Community::NotificationAccess.visible?(
        notification: notification,
        user: @recipient
      )
      assert_no_emails do
        Community::ForumMailer
          .tag_topic(@recipient.id, @topic.public_id, [ tag.id ])
          .deliver_now
      end
    end

    private

    def create_conversation(*users)
      conversation = Community::Conversation.create!(title: "Access test DM")
      users.each do |user|
        Community::ConversationParticipant.create!(conversation: conversation, user: user)
      end
      conversation
    end

    def create_tag(name, staff_only: false)
      Community::Tag.create!(
        name: name,
        slug: "#{name.parameterize}-#{SecureRandom.hex(4)}",
        staff_only: staff_only
      )
    end

    def subscribe(user, tag)
      Community::Subscription.create!(
        user: user,
        subscribable: tag,
        notification_level: "watching"
      )
    end

    def enable_tag_notifications(user)
      NotificationPreference.set!(
        user,
        channel: "in_app",
        notification_type: "forum.tag_topic",
        enabled: true
      )
      NotificationPreference.set!(
        user,
        channel: "email",
        notification_type: "forum.tag_topic",
        enabled: true
      )
    end
  end
end
