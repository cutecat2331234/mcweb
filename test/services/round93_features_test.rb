# frozen_string_literal: true

require "test_helper"

class Round93BadgeEarnedEmailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @badge = Community::Badge.find_or_create_by!(slug: "r93-badge") do |b|
      b.name = "R93 Badge"
      b.grant_rule = "manual"
    end
    NotificationPreference.set!(@user, channel: "email", notification_type: "forum.badge", enabled: true)
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "forum.badge", enabled: false)
  end

  test "badge earned enqueues email" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyBadgeEarned.call(user: @user, badge: @badge)
    end
  end
end

class Round93TopicAssignedEmailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @actor = create_user
    grant_permission(@actor, "forum.topics.lock")
    @assignee = create_user
    category = Community::Category.find_or_create_by!(slug: "r93-assign") { |c| c.name = "A" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r93-assign-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @actor,
      title: "Assign me",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @actor,
      replies_count: 0
    )
    NotificationPreference.set!(@assignee, channel: "email", notification_type: "forum.topic_assigned", enabled: true)
    NotificationPreference.set!(@assignee, channel: "in_app", notification_type: "forum.topic_assigned", enabled: false)
  end

  test "topic assigned enqueues email" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyTopicAssigned.call(topic: @topic, assignee: @assignee, actor: @actor)
    end
  end
end

class Round93TrustLevelEmailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "email", notification_type: "forum.trust_level", enabled: true)
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "forum.trust_level", enabled: false)
  end

  test "trust level up enqueues email" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyTrustLevelUp.call(user: @user, level: 2, level_name: "Member")
    end
  end
end

class Round93OrderCreatedPaymentLinkTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("store.pending_order_expiry_minutes", "30")
    @user = create_user
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.order_created", enabled: true)
    @order = Commerce::Order.create!(
      public_id: "ord_r93_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY",
      created_at: 5.minutes.ago
    )
  end

  test "order created email includes pay url" do
    mail = Commerce::OrderMailer.order_created(@order.id)
    assert_includes mail.body.encoded, @order.public_id
    assert_includes mail.body.encoded, "立即支付"
  end
end

class Round93PaymentReminderSkipTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.pending_order_expiry_minutes", "30")
    @user = create_user
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.payment_reminder", enabled: false)
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.payment_reminder", enabled: false)
    @order = Commerce::Order.create!(
      public_id: "ord_r93_skip_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY",
      created_at: 20.minutes.ago
    )
  end

  test "payment reminder does not mark sent when notifications disabled" do
    assert_no_enqueued_jobs only: MailDeliveryJob do
      Commerce::PendingOrderPaymentReminderJob.perform_now
    end
    assert_nil @order.reload.payment_reminder_sent_at
  end
end

class Round93LatestBulkModerateIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    sign_in_as(@mod)
  end

  test "latest page includes bulk moderate url for staff" do
    get forum_latest_path
    assert_response :success
    assert_includes response.body, "bulkModerateUrl"
  end
end

class Round93SearchBulkModerateIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    sign_in_as(@mod)
  end

  test "search page includes bulk moderate url for staff" do
    get forum_search_path, params: { q: "test" }
    assert_response :success
    assert_includes response.body, "bulkModerateUrl"
  end
end

class Round93BulkUnlockTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r93-unlock") { |c| c.name = "U" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r93-unlock-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @mod,
      title: "Locked #{SecureRandom.hex(4)}",
      status: "published",
      locked: true,
      last_posted_at: Time.current,
      last_post_user: @mod,
      replies_count: 0
    )
  end

  test "bulk unlock topics" do
    result = Community::BulkModerateTopics.call(
      user: @mod,
      topic_public_ids: [ @topic.public_id ],
      action: "unlock"
    )
    assert result.success?
    assert_not @topic.reload.locked?
  end
end
