# frozen_string_literal: true

require "test_helper"

class NotifyPostReplyTest < ActiveSupport::TestCase
  setup do
    @op = create_user
    @replier = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    @topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: @section, user: @op, title: "T", status: "published",
      last_posted_at: Time.current, last_post_user: @op, replies_count: 0
    )
    @parent = Community::Post.create!(topic: @topic, user: @op, floor_number: 1, body: "opening", status: "published")
  end

  test "notifies the parent post author" do
    reply = build_reply(author: @replier, parent: @parent)
    assert_difference -> { replies_for(@op).count }, 1 do
      Community::NotifyPostReply.call(post: reply, replier: @replier, parent_post: @parent)
    end
    meta = replies_for(@op).last.metadata
    assert_equal @topic.public_id, meta["topic_id"]
    assert_equal @parent.id, meta["parent_post_id"]
  end

  test "does not notify on a self-reply" do
    reply = build_reply(author: @op, parent: @parent)
    assert_no_difference -> { Notification.where(notification_type: "forum.post_reply").count } do
      Community::NotifyPostReply.call(post: reply, replier: @op, parent_post: @parent)
    end
  end

  test "skips when the reply also quotes the parent (quote notification covers it)" do
    reply = build_reply(author: @replier, parent: @parent, quoted: @parent)
    assert_no_difference -> { Notification.where(notification_type: "forum.post_reply").count } do
      Community::NotifyPostReply.call(post: reply, replier: @replier, parent_post: @parent)
    end
  end

  test "respects the recipient in-app preference" do
    NotificationPreference.set!(@op, channel: "in_app", notification_type: "forum.post_reply", enabled: false)
    reply = build_reply(author: @replier, parent: @parent)
    assert_no_difference -> { Notification.where(notification_type: "forum.post_reply").count } do
      Community::NotifyPostReply.call(post: reply, replier: @replier, parent_post: @parent)
    end
  end

  test "fires through the publish pipeline" do
    reply = build_reply(author: @replier, parent: @parent)
    assert_difference -> { replies_for(@op).count }, 1 do
      Community::PublishPostSideEffects.call(post: reply)
    end
  end

  private

  def build_reply(author:, parent:, quoted: nil)
    floor = @topic.posts.maximum(:floor_number).to_i + 1
    Community::Post.create!(
      topic: @topic, user: author, floor_number: floor, body: "a reply",
      status: "published", parent_post: parent, quoted_post: quoted
    )
  end

  def replies_for(user)
    Notification.where(user: user, notification_type: "forum.post_reply")
  end
end
