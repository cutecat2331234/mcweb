# frozen_string_literal: true

require "test_helper"

class Round92BulkModerateTopicsTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r92-bulk") { |c| c.name = "B" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r92-bulk-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @mod,
      title: "Bulk mod #{SecureRandom.hex(4)}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @mod,
      replies_count: 0
    )
  end

  test "bulk lock topics" do
    result = Community::BulkModerateTopics.call(
      user: @mod,
      topic_public_ids: [ @topic.public_id ],
      action: "lock"
    )
    assert result.success?
    assert_equal 1, result.value[:moderated]
    assert @topic.reload.locked?
  end

  test "rejects unsupported action" do
    result = Community::BulkModerateTopics.call(
      user: @mod,
      topic_public_ids: [ @topic.public_id ],
      action: "pin"
    )
    assert result.failure?
  end
end

class Round92BadgesGalleryTest < ActionDispatch::IntegrationTest
  setup do
    @badge = Community::Badge.create!(
      name: "Gallery Badge",
      slug: "gallery-#{SecureRandom.hex(4)}",
      icon: "🏅",
      grant_rule: "manual"
    )
    @user = create_user
    Community::UserBadge.create!(user: @user, badge: @badge, granted_at: 1.day.ago)
  end

  test "badges index page" do
    get forum_badges_path
    assert_response :success
    assert_includes response.body, @badge.name
  end

  test "badge show page includes holder" do
    get forum_badge_path(@badge.slug)
    assert_response :success
    assert_includes response.body, @user.username
    assert_includes response.body, "granted_at"
  end
end

class Round92UserBadgeGrantedAtTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @badge = Community::Badge.create!(
      name: "Profile Badge",
      slug: "profile-#{SecureRandom.hex(4)}",
      icon: "⭐",
      grant_rule: "manual"
    )
    Community::UserBadge.create!(user: @user, badge: @badge, granted_at: Time.current)
    sign_in_as(@user)
  end

  test "user profile includes granted_at on badges" do
    get forum_user_path(@user.username)
    assert_response :success
    assert_includes response.body, "granted_at"
    assert_includes response.body, @badge.slug
  end
end

class Round92PendingOrderPaymentReminderJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.pending_order_expiry_minutes", "30")
    @user = create_user
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.payment_reminder", enabled: true)
    @order = Commerce::Order.create!(
      public_id: "ord_r92_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY",
      created_at: 20.minutes.ago
    )
  end

  test "sends payment reminder for halfway expired order" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Commerce::PendingOrderPaymentReminderJob.perform_now
    end
    assert @order.reload.payment_reminder_sent_at.present?
  end

  test "skips order already reminded" do
    @order.update_column(:payment_reminder_sent_at, Time.current)
    assert_no_enqueued_jobs only: MailDeliveryJob do
      Commerce::PendingOrderPaymentReminderJob.perform_now
    end
  end
end

class Round92BulkModerateIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r92-int") { |c| c.name = "I" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r92-int-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @mod,
      title: "Integration #{SecureRandom.hex(4)}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @mod,
      replies_count: 0
    )
    sign_in_as(@mod)
  end

  test "bulk moderate endpoint locks topics" do
    patch bulk_moderate_forum_topics_path, params: { topic_ids: [ @topic.public_id ], action_type: "lock" }
    assert_redirected_to forum_latest_path
    assert @topic.reload.locked?
  end

  test "section page includes bulk moderate url for staff" do
    get forum_section_path(@topic.section)
    assert_response :success
    assert_includes response.body, "bulkModerateUrl"
  end
end
