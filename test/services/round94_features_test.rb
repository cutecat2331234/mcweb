# frozen_string_literal: true

require "test_helper"

class Round94ReactionEmailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @reactor = create_user
    category = Community::Category.find_or_create_by!(slug: "r94-react") { |c| c.name = "R" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r94-react-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "React topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 1,
      body: "Hello",
      status: "published"
    )
    NotificationPreference.set!(@author, channel: "email", notification_type: "forum.reaction", enabled: true)
    NotificationPreference.set!(@author, channel: "in_app", notification_type: "forum.reaction", enabled: false)
  end

  test "reaction enqueues email when enabled" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyPostReaction.call(post: @post, reactor: @reactor, emoji: "👍")
    end
  end
end

class Round94QuoteEmailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @quoter = create_user
    category = Community::Category.find_or_create_by!(slug: "r94-quote") { |c| c.name = "Q" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r94-quote-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Quote topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @quoted = Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 1,
      body: "Original",
      status: "published"
    )
    @post = Community::Post.create!(
      topic: @topic,
      user: @quoter,
      floor_number: 2,
      body: "Reply",
      quoted_post: @quoted,
      status: "published"
    )
    NotificationPreference.set!(@author, channel: "email", notification_type: "forum.quote", enabled: true)
    NotificationPreference.set!(@author, channel: "in_app", notification_type: "forum.quote", enabled: false)
  end

  test "quote enqueues email when enabled" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyPostQuoted.call(post: @post, quoter: @quoter, quoted_post: @quoted)
    end
  end
end

class Round94BookmarkReminderEmailOnlyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r94-bm") { |c| c.name = "B" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r94-bm-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Bookmark topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @bookmark = Community::Bookmark.create!(
      user: @user,
      topic: @topic,
      remind_at: 1.minute.ago
    )
    NotificationPreference.set!(@user, channel: "email", notification_type: "forum.bookmark_reminder", enabled: true)
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "forum.bookmark_reminder", enabled: false)
  end

  test "email-only bookmark reminder sends mail and clears remind_at" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyBookmarkReminder.call(bookmark: @bookmark)
    end
    assert_nil @bookmark.reload.remind_at
  end
end

class Round94BulkModerateReturnToTest < ActionDispatch::IntegrationTest
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r94-ret") { |c| c.name = "R" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r94-ret-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @mod,
      title: "Return #{SecureRandom.hex(4)}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @mod,
      replies_count: 0
    )
    sign_in_as(@mod)
  end

  test "bulk moderate redirects to return_to" do
    patch bulk_moderate_forum_topics_path,
      params: { topic_ids: [ @topic.public_id ], action_type: "lock", return_to: admin_forum_topics_path }
    assert_redirected_to admin_forum_topics_path
  end
end

class Round94BulkUpdateOrdersTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    grant_permission(@admin, "store.orders.read")
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_r94_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  test "bulk cancel pending orders" do
    result = Commerce::BulkUpdateOrders.call(
      actor: @admin,
      order_public_ids: [ @order.public_id ],
      action: "cancel_pending"
    )
    assert result.success?
    assert_equal 1, result.value[:processed]
    assert_equal "cancelled", @order.reload.status
  end

  test "bulk mark fulfilled" do
    @order.update!(status: "paid")
    result = Commerce::BulkUpdateOrders.call(
      actor: @admin,
      order_public_ids: [ @order.public_id ],
      action: "mark_fulfilled"
    )
    assert result.success?
    assert_equal "fulfilled", @order.reload.status
  end
end

class Round94UserCardGrantedAtTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @badge = Community::Badge.create!(
      name: "Hover Badge",
      slug: "hover-#{SecureRandom.hex(4)}",
      icon: "⭐",
      grant_rule: "manual"
    )
    Community::UserBadge.create!(user: @user, badge: @badge, granted_at: Time.current)
    sign_in_as(@user)
  end

  test "user card includes granted_at on badges" do
    get card_forum_user_path(@user.username), headers: { "Accept" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body["badges"].first["granted_at"].present?
  end
end
