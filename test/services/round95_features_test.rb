# frozen_string_literal: true

require "test_helper"

class Round95TopicInviteEmailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @inviter = create_user
    @invitee = create_user
    category = Community::Category.find_or_create_by!(slug: "r95-invite") { |c| c.name = "R95" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r95-invite-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @inviter,
      title: "Invite topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @inviter,
      replies_count: 0
    )
    @invite = Community::TopicInvite.create!(topic: @topic, user: @invitee, invited_by: @inviter)
    NotificationPreference.set!(@invitee, channel: "email", notification_type: "forum.topic_invite", enabled: true)
    NotificationPreference.set!(@invitee, channel: "in_app", notification_type: "forum.topic_invite", enabled: false)
  end

  test "topic invite enqueues email when enabled" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyTopicInvite.call(invite: @invite)
    end
  end
end

class Round95PollClosedTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @voter = create_user
    category = Community::Category.find_or_create_by!(slug: "r95-poll") { |c| c.name = "P" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r95-poll-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Poll topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @poll = Community::Poll.create!(topic: @topic, question: "Pick one?", options: %w[A B])
    Community::PollVote.create!(poll: @poll, user: @voter, option_index: 0)
    NotificationPreference.set!(@author, channel: "in_app", notification_type: "forum.poll_closed", enabled: false)
    NotificationPreference.set!(@voter, channel: "in_app", notification_type: "forum.poll_closed", enabled: true)
    NotificationPreference.set!(@voter, channel: "email", notification_type: "forum.poll_closed", enabled: false)
  end

  test "close poll creates small action and notifies voters" do
    assert_difference -> { @topic.posts.where(post_type: "small_action").count }, 1 do
      assert_difference -> { Notification.where(notification_type: "forum.poll_closed").count }, 1 do
        result = Community::ClosePoll.call(user: @author, poll: @poll)
        assert result.success?
      end
    end
    assert_not @poll.reload.open?
  end

  test "expired poll job finalizes once" do
    @poll.update!(closes_at: 1.hour.ago, updated_at: 2.hours.ago)
    assert_difference -> { @topic.posts.where(post_type: "small_action").count }, 1 do
      Community::CloseExpiredPollsJob.perform_now
    end
    assert_no_difference -> { @topic.posts.where(post_type: "small_action").count } do
      Community::CloseExpiredPollsJob.perform_now
    end
  end
end

class Round95BulkMarkPaidTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    grant_permission(@admin, "store.orders.read")
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_r95_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  test "bulk mark paid transitions order" do
    result = Commerce::BulkUpdateOrders.call(
      actor: @admin,
      order_public_ids: [ @order.public_id ],
      action: "mark_paid"
    )
    assert result.success?
    assert_equal 1, result.value[:processed]
    assert_equal "paid", @order.reload.status
  end

  test "bulk mark paid resumes stuck paid order without re-marking" do
    @order.update!(status: "paid")

    assert_enqueued_with(job: Commerce::FulfillOrderJob, args: [ @order.id ]) do
      result = Commerce::BulkUpdateOrders.call(
        actor: @admin,
        order_public_ids: [ @order.public_id ],
        action: "mark_paid"
      )
      assert result.success?
      assert_equal 1, result.value[:processed]
    end

    assert_equal "paid", @order.reload.status
  end

  test "bulk mark paid resumes processing order missing post payment side effects" do
    @order.update!(status: "processing")

    assert_enqueued_with(job: Commerce::PostPaymentSideEffectsJob, args: [ @order.id ]) do
      result = Commerce::BulkUpdateOrders.call(
        actor: @admin,
        order_public_ids: [ @order.public_id ],
        action: "mark_paid"
      )
      assert result.success?
      assert_equal 1, result.value[:processed]
    end

    assert_equal "processing", @order.reload.status
  end
end

class Round95AuthorBadgesGrantedAtTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    @reader = create_user
    @badge = Community::Badge.create!(
      name: "Inline Badge",
      slug: "inline-#{SecureRandom.hex(4)}",
      icon: "🏅",
      grant_rule: "manual"
    )
    Community::UserBadge.create!(user: @author, badge: @badge, granted_at: Time.current)
    category = Community::Category.find_or_create_by!(slug: "r95-badge") { |c| c.name = "B" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r95-badge-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Badge topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 1,
      body: "Hello",
      status: "published"
    )
    sign_in_as(@reader)
  end

  test "topic show includes granted_at on author badges" do
    get forum_topic_path(@topic)
    assert_response :success
    assert_includes response.body, "granted_at"
  end
end

class Round95SearchExcludeTermsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "search passes exclude terms to frontend" do
    get forum_search_path(q: "ruby -spam -offtopic")
    assert_response :success
    assert_includes response.body, "excludeTerms"
    assert_includes response.body, "spam"
    assert_includes response.body, "offtopic"
  end

  test "saved search filter summary includes exclude chips" do
    labels = Community::SavedSearchFilterSummary.call(
      Struct.new(:query, :filters, keyword_init: true).new(query: "ruby -spam", filters: {})
    )
    assert_includes labels, "排除：spam"
  end
end

class Round95AdminOrdersExportTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "store.orders.read")
    @user = create_user
    @pending = Commerce::Order.create!(
      public_id: "ord_r95p_#{SecureRandom.hex(8)}",
      order_number: "PEND#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 500,
      total_cents: 500,
      currency: "CNY"
    )
    @paid = Commerce::Order.create!(
      public_id: "ord_r95a_#{SecureRandom.hex(8)}",
      order_number: "PAID#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 900,
      total_cents: 900,
      currency: "CNY"
    )
    sign_in_as(@admin)
  end

  test "orders index includes status tabs" do
    get admin_store_orders_path
    assert_response :success
    assert_includes response.body, "statusTabs"
  end

  test "export respects status filter" do
    get export_admin_store_orders_path(status: "pending")
    assert_response :success
    assert_includes response.body, @pending.order_number
    assert_not_includes response.body, @paid.order_number
  end
end
