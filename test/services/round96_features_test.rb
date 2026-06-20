# frozen_string_literal: true

require "test_helper"

class Round96DigestTypesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @user.update!(forum_digest_frequency: "daily", forum_digest_last_sent_at: 2.days.ago)
    NotificationPreference.set!(@user, channel: "email", notification_type: "forum.badge", enabled: true)
    Notification.create!(
      user: @user,
      notification_type: "forum.badge",
      title: "Badge",
      body: "You earned a badge",
      metadata: { badge_slug: "test", path: "/forum/badges/test" }
    )
  end

  test "digest includes badge notifications" do
    assert_includes Community::SendForumDigest::NOTIFICATION_TYPES, "forum.badge"
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::SendForumDigest.call(user: @user)
    end
  end

  test "reaction email deferred when digest enabled" do
    @author = create_user
    @reactor = create_user
    category = Community::Category.find_or_create_by!(slug: "r96-react") { |c| c.name = "R" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r96-react-sec") { |s| s.name = "S"; s.position = 0 }
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "React",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    post = Community::Post.create!(topic: topic, user: @author, floor_number: 1, body: "Hi", status: "published")
    @author.update!(forum_digest_frequency: "daily")
    NotificationPreference.set!(@author, channel: "email", notification_type: "forum.reaction", enabled: true)
    NotificationPreference.set!(@author, channel: "in_app", notification_type: "forum.reaction", enabled: false)

    assert_no_enqueued_jobs only: MailDeliveryJob do
      Community::NotifyPostReaction.call(post: post, reactor: @reactor, emoji: "👍")
    end
  end
end

class Round96BulkMarkPaidNotifyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "store.orders.read")
    @user = create_user
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.payment_confirmed", enabled: true)
    @order = Commerce::Order.create!(
      public_id: "ord_r96_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  test "bulk mark paid sends payment confirmed email" do
    assert_enqueued_with(job: Commerce::PostPaymentSideEffectsJob, args: [ @order.id ]) do
      result = Commerce::BulkUpdateOrders.call(
        actor: @admin,
        order_public_ids: [ @order.public_id ],
        action: "mark_paid"
      )
      assert result.success?
    end

    assert_enqueued_jobs 1, only: MailDeliveryJob do
      perform_enqueued_jobs(only: Commerce::PostPaymentSideEffectsJob)
    end

    assert_equal "paid", @order.reload.status
    assert Notification.exists?(user: @user, notification_type: "commerce.payment_confirmed")
  end
end

class Round96OrderStatusTabsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "store.orders.read")
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r96p_#{SecureRandom.hex(8)}",
      order_number: "PEND#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 500,
      total_cents: 500,
      currency: "CNY"
    )
    Commerce::Order.create!(
      public_id: "ord_r96a_#{SecureRandom.hex(8)}",
      order_number: "PAID#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 900,
      total_cents: 900,
      currency: "CNY"
    )
    sign_in_as(@admin)
  end

  test "orders index status tabs include counts" do
    get admin_store_orders_path
    assert_response :success
    assert_includes response.body, '"count"'
  end
end

class Round96SearchExcludeRemoveTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "search page passes exclude terms for chip display" do
    get forum_search_path(q: "ruby -spam")
    assert_response :success
    assert_includes response.body, "excludeTerms"
    assert_includes response.body, "spam"
  end
end

class Round96HereMailerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @participant = create_user
    category = Community::Category.find_or_create_by!(slug: "r96-here") { |c| c.name = "H" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r96-here-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Here topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @participant, floor_number: 1, body: "Hi", status: "published")
    @post = Community::Post.create!(topic: @topic, user: @author, floor_number: 2, body: "@here check this", status: "published")
    NotificationPreference.set!(@participant, channel: "in_app", notification_type: "forum.here", enabled: true)
    NotificationPreference.set!(@participant, channel: "email", notification_type: "forum.here", enabled: true)
    @participant.update!(forum_digest_frequency: "none")
  end

  test "here mention enqueues here mailer" do
    assert_enqueued_with(job: MailDeliveryJob, args: [ "Community::ForumMailer", "here", "deliver_now", { args: [ @participant.id, @topic.public_id, @post.id ] } ]) do
      Community::ProcessMentions.call(body: "@here check this", author: @author, post: @post, topic: @topic)
    end
  end
end
