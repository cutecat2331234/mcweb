# frozen_string_literal: true

require "test_helper"

class NotifyTopicLinkedTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @op = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
  end

  test "notifies the linked topic's author" do
    linked = make_topic(owner: @op, title: "Linked")
    source = make_topic(owner: @author, title: "Source")
    post = reply(topic: source, body: "see /app/forum/topics/#{linked.public_id} for details")

    assert_difference -> { linked_notifications(@op).count }, 1 do
      Community::NotifyTopicLinked.call(post: post, author: @author)
    end

    meta = linked_notifications(@op).last.metadata
    assert_equal source.public_id, meta["topic_id"]
    assert_equal linked.public_id, meta["linked_topic_id"]
  end

  test "matches full host URLs and anchors" do
    linked = make_topic(owner: @op)
    source = make_topic(owner: @author)
    post = reply(topic: source, body: "https://example.com/app/forum/topics/#{linked.public_id}#post-9 yo")

    assert_difference -> { linked_notifications(@op).count }, 1 do
      Community::NotifyTopicLinked.call(post: post, author: @author)
    end
  end

  test "does not notify when linking your own topic" do
    own = make_topic(owner: @author, title: "Own")
    source = make_topic(owner: @author, title: "Source")
    post = reply(topic: source, body: "ref /app/forum/topics/#{own.public_id}")

    assert_no_difference -> { Notification.where(notification_type: "forum.linked").count } do
      Community::NotifyTopicLinked.call(post: post, author: @author)
    end
  end

  test "ignores a self-link to the post's own topic" do
    source = make_topic(owner: @author, title: "Source")
    post = reply(topic: source, body: "loop /app/forum/topics/#{source.public_id}")

    assert_no_difference -> { Notification.where(notification_type: "forum.linked").count } do
      Community::NotifyTopicLinked.call(post: post, author: @author)
    end
  end

  test "dedupes multiple links to the same topic into one notification" do
    linked = make_topic(owner: @op)
    source = make_topic(owner: @author)
    post = reply(topic: source, body: "a /forum/topics/#{linked.public_id} and again /forum/topics/#{linked.public_id}")

    assert_difference -> { linked_notifications(@op).count }, 1 do
      Community::NotifyTopicLinked.call(post: post, author: @author)
    end
  end

  test "respects the recipient's in-app preference" do
    linked = make_topic(owner: @op)
    source = make_topic(owner: @author)
    NotificationPreference.set!(@op, channel: "in_app", notification_type: "forum.linked", enabled: false)
    post = reply(topic: source, body: "ref /forum/topics/#{linked.public_id}")

    assert_no_difference -> { Notification.where(notification_type: "forum.linked").count } do
      Community::NotifyTopicLinked.call(post: post, author: @author)
    end
  end

  test "does not notify a user who blocked the author" do
    linked = make_topic(owner: @op)
    source = make_topic(owner: @author)
    Community::UserBlock.create!(blocker: @op, blocked: @author)
    post = reply(topic: source, body: "ref /forum/topics/#{linked.public_id}")

    assert_no_difference -> { Notification.where(notification_type: "forum.linked").count } do
      Community::NotifyTopicLinked.call(post: post, author: @author)
    end
  end

  test "does not notify when the source topic is unlisted" do
    linked = make_topic(owner: @op)
    source = make_topic(owner: @author)
    source.update!(unlisted: true)
    post = reply(topic: source, body: "ref /forum/topics/#{linked.public_id}")

    assert_no_difference -> { Notification.where(notification_type: "forum.linked").count } do
      Community::NotifyTopicLinked.call(post: post, author: @author)
    end
  end

  test "fires through the publish pipeline for an opening post" do
    linked = make_topic(owner: @op)
    source = make_topic(owner: @author, body: "intro /app/forum/topics/#{linked.public_id}")
    opening = source.posts.find_by!(floor_number: 1)

    assert_difference -> { linked_notifications(@op).count }, 1 do
      Community::PublishPostSideEffects.call(post: opening)
    end
  end

  private

  def make_topic(owner:, title: "T", body: "opening post")
    topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: @section, user: owner, title: title, status: "published",
      last_posted_at: Time.current, last_post_user: owner, replies_count: 0
    )
    Community::Post.create!(topic: topic, user: owner, floor_number: 1, body: body, status: "published")
    topic
  end

  def reply(topic:, body:, author: @author)
    floor = topic.posts.maximum(:floor_number).to_i + 1
    Community::Post.create!(topic: topic, user: author, floor_number: floor, body: body, status: "published")
  end

  def linked_notifications(user)
    Notification.where(user: user, notification_type: "forum.linked")
  end
end
