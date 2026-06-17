# frozen_string_literal: true

require "test_helper"

class Round91ParseSearchExcludeTest < ActiveSupport::TestCase
  test "parses exclude terms from query" do
    result = Community::ParseSearchQuery.call(query: "ruby -spam -offtopic tutorial")
    assert result.success?
    assert_equal "ruby tutorial", result.value[:query]
    assert_equal %w[spam offtopic], result.value[:exclude_terms]
  end
end

class Round91ApplySearchExclusionsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r91-excl") { |c| c.name = "E" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r91-excl-sec") { |s| s.name = "S"; s.position = 0 }
    @included = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Ruby tutorial #{SecureRandom.hex(4)}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(
      topic: @included,
      user: @user,
      floor_number: 1,
      body: "Learn ruby basics",
      status: "published"
    )
    @excluded = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Ruby spam #{SecureRandom.hex(4)}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(
      topic: @excluded,
      user: @user,
      floor_number: 1,
      body: "spam content here",
      status: "published"
    )
  end

  test "excludes topics matching exclude terms" do
    scope = Community::Topic.where(id: [ @included.id, @excluded.id ])
    result = Community::ApplySearchExclusions.call(scope: scope, exclude_terms: %w[spam])
    assert result.success?
    ids = result.value.pluck(:id)
    assert_includes ids, @included.id
    assert_not_includes ids, @excluded.id
  end
end

class Round91SavedSearchInAppTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "forum.saved_search_match", enabled: true)
    @search = Community::SavedSearch.create!(
      user: @user,
      name: "In-app",
      query: "test",
      filters: {},
      notify_in_app: true,
      notify_daily: false
    )
    category = Community::Category.find_or_create_by!(slug: "r91-inapp") { |c| c.name = "I" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r91-inapp-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "test match #{SecureRandom.hex(4)}",
      body: "Body content here",
      ip_address: "127.0.0.1"
    ).value
  end

  test "digest sends in-app notification when enabled" do
    assert_difference -> { Notification.where(user: @user, notification_type: "forum.saved_search_match").count }, 1 do
      Community::SendSavedSearchDigests.new.send(:send_for_search, @search)
    end
  end
end

class Round91MarkTopicsReadTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r91-read") { |c| c.name = "R" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r91-read-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "Unread #{SecureRandom.hex(4)}",
      body: "Body content",
      ip_address: "127.0.0.1"
    ).value
    Community::ReadState.mark_read!(@user, @topic, floor: 0)
  end

  test "marks selected topics read" do
    result = Community::MarkTopicsRead.call(user: @user, topic_public_ids: [ @topic.public_id ])
    assert result.success?
    assert_equal 1, result.value[:marked]
    assert_not Community::ReadState.with_unread_for(@user).where(forum_topic_id: @topic.id).exists?
  end
end

class Round91ConversationMuteTest < ActiveSupport::TestCase
  setup do
    @sender = create_user
    enable_forum_pm!(@sender)
    @recipient = create_user
    NotificationPreference.set!(@recipient, channel: "in_app", notification_type: "forum.private_message", enabled: true)
    result = Community::CreateConversation.call(
      sender: @sender,
      recipient_username: @recipient.username,
      body: "Hello there friend"
    )
    assert result.success?, result.error || result.errors.inspect
    @conversation = result.value[:conversation]
    participant = @conversation.participants.find_by(user: @recipient)
    participant.update!(muted_at: Time.current)
  end

  test "muted participant skips private message notification" do
    message = @conversation.messages.create!(user: @sender, body: "Another message")
    assert_no_difference -> { Notification.where(user: @recipient, notification_type: "forum.private_message").count } do
      Community::NotifyPrivateMessage.call(message: message, conversation: @conversation)
    end
  end

  test "toggle conversation mute" do
    result = Community::ToggleConversationMute.call(user: @recipient, conversation: @conversation)
    assert result.success?
    refute result.value[:muted]
  end
end

class Round91UnreadSelectedReadIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r91-int") { |c| c.name = "I" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r91-int-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "Integration #{SecureRandom.hex(4)}",
      body: "Body content",
      ip_address: "127.0.0.1"
    ).value
    Community::ReadState.mark_read!(@user, @topic, floor: 0)
    sign_in_as(@user)
  end

  test "mark selected read endpoint" do
    patch forum_unread_mark_selected_read_path, params: { topic_ids: [ @topic.public_id ] }
    assert_redirected_to forum_unread_path
    assert_not Community::ReadState.with_unread_for(@user).where(forum_topic_id: @topic.id).exists?
  end

  test "unread page includes mark selected url" do
    get forum_unread_path
    assert_response :success
    assert_includes response.body, "markSelectedReadUrl"
  end
end

class Round91RetryFailedOrderWebhooksJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @delivery = Commerce::OrderWebhookDelivery.create!(
      event_type: "order.test",
      url: "https://example.com/hook",
      status: "pending",
      attempt_count: 1,
      request_payload: { "event" => "order.test", "test" => true },
      created_at: 10.minutes.ago
    )
  end

  test "requeues stale pending delivery" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      Commerce::RetryFailedOrderWebhooksJob.perform_now
    end
  end
end
