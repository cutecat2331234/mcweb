# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class CommunityNotificationAccessTest < ActionDispatch::IntegrationTest
  include InertiaRails::Minitest

  setup do
    suffix = SecureRandom.hex(4)
    category = Community::Category.create!(
      name: "Notification list access",
      slug: "notification-list-access-#{suffix}"
    )
    @section = Community::Section.create!(
      category: category,
      name: "Notification list access",
      slug: "notification-list-section-#{suffix}",
      position: 0
    )
    @user = create_user
    @author = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Notification list topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    sign_in_as(@user)
  end

  test "notification list and visit do not expose a conversation after membership is removed" do
    conversation = Community::Conversation.create!(title: "Revoked DM")
    participant = Community::ConversationParticipant.create!(
      conversation: conversation,
      user: @user
    )
    Community::ConversationParticipant.create!(
      conversation: conversation,
      user: @author
    )
    notification = @user.notifications.create!(
      notification_type: "forum.private_message",
      title: "PRIVATE-CONVERSATION-TITLE",
      body: "PRIVATE-CONVERSATION-BODY",
      metadata: {
        conversation_id: conversation.id,
        path: "/app/forum/conversations/#{conversation.id}"
      }
    )
    participant.destroy!

    get account_notifications_path, headers: inertia_headers
    assert_response :success
    assert_not_includes response.body, "PRIVATE-CONVERSATION-TITLE"
    assert_not_includes response.body, "PRIVATE-CONVERSATION-BODY"
    assert_not_includes response.body, "/app/forum/conversations/#{conversation.id}"

    get visit_account_notification_path(notification)
    assert_redirected_to account_notifications_path
  end

  test "notification list does not expose tag names after unsubscribe" do
    tag = Community::Tag.create!(
      name: "UNSUBSCRIBED-SECRET-TAG",
      slug: "unsubscribed-secret-tag-#{SecureRandom.hex(4)}"
    )
    @topic.tags << tag
    subscription = Community::Subscription.create!(
      user: @user,
      subscribable: tag,
      notification_level: "watching"
    )
    @user.notifications.create!(
      notification_type: "forum.tag_topic",
      title: "TAG-NOTIFICATION-TITLE",
      body: "Watched tag: #{tag.name}",
      metadata: {
        topic_id: @topic.public_id,
        tag_ids: [ tag.id ],
        path: "/app/forum/topics/#{@topic.public_id}"
      }
    )
    subscription.destroy!

    get account_notifications_path, headers: inertia_headers
    assert_response :success
    assert_not_includes response.body, tag.name
    assert_not_includes response.body, "TAG-NOTIFICATION-TITLE"
  end

  test "notifications API redacts inaccessible conversation content" do
    conversation = Community::Conversation.create!(title: "API revoked DM")
    participant = Community::ConversationParticipant.create!(
      conversation: conversation,
      user: @user
    )
    Community::ConversationParticipant.create!(
      conversation: conversation,
      user: @author
    )
    notification = @user.notifications.create!(
      notification_type: "forum.private_message",
      title: "API-PRIVATE-TITLE",
      body: "API-PRIVATE-BODY",
      metadata: {
        conversation_id: conversation.id,
        path: "/app/forum/conversations/#{conversation.id}"
      }
    )
    participant.destroy!
    _record, token = Administration::ApiKey.generate!(
      name: "notification-access-#{SecureRandom.hex(4)}",
      scopes: %w[read],
      user: @user
    )

    get "/api/v1/notifications", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
    row = JSON.parse(response.body).fetch("data").find { |item| item["id"] == notification.id }
    assert_equal false, row["content_available"]
    assert_nil row["title"]
    assert_nil row["body"]
    assert_nil row["url"]
  end

  test "web and API redact a post notification after soft deletion" do
    post = Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 1,
      body: "SOFT-DELETED-POST-BODY",
      status: "published"
    )
    notification = @user.notifications.create!(
      notification_type: "forum.mention",
      title: "SOFT-DELETED-POST-TITLE",
      body: post.body,
      metadata: {
        topic_id: @topic.public_id,
        post_id: post.id,
        path: "/app/forum/topics/#{@topic.public_id}#post-#{post.id}"
      }
    )
    post.soft_delete!

    get account_notifications_path, headers: inertia_headers
    assert_response :success
    assert_not_includes response.body, "SOFT-DELETED-POST-TITLE"
    assert_not_includes response.body, "SOFT-DELETED-POST-BODY"
    assert_not_includes response.body, "#post-#{post.id}"

    _record, token = Administration::ApiKey.generate!(
      name: "soft-delete-notification-#{SecureRandom.hex(4)}",
      scopes: %w[read],
      user: @user
    )
    get "/api/v1/notifications",
        headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
    row = JSON.parse(response.body).fetch("data").find do |item|
      item["id"] == notification.id
    end
    assert_equal false, row["content_available"]
    assert_nil row["title"]
    assert_nil row["body"]
    assert_nil row["url"]
  end

  test "the notification centre paginates beyond the first fifty items" do
    55.times do |index|
      @user.notifications.create!(
        notification_type: "system.notice",
        title: format("PAGEABLE-%02d", index),
        body: "Pagination fixture",
        created_at: 55.minutes.ago + index.minutes
      )
    end

    get account_notifications_path(page: 2), headers: inertia_headers

    assert_response :success
    props = inertia.props.deep_symbolize_keys
    assert_equal 2, props.dig(:pagination, :page)
    assert_equal 55, props.dig(:pagination, :count)
    titles = props.fetch(:notificationGroups)
      .flat_map { |group| group.fetch(:items) }
      .map { |notification| notification[:title] }
    assert_includes titles, "PAGEABLE-00"
    refute_includes titles, "PAGEABLE-54"
  end

  test "a user can delete only their own individual notification and keep list filters" do
    own = @user.notifications.create!(
      notification_type: "system.notice",
      title: "Delete this notification"
    )
    foreign = @author.notifications.create!(
      notification_type: "system.notice",
      title: "Do not delete this notification"
    )

    delete account_notification_path(own), params: {
      category: "system",
      read: "unread",
      type: "system.notice",
      period: "this_month",
      page: "2"
    }
    assert_redirected_to account_notifications_path(
      category: "system",
      read: "unread",
      type: "system.notice",
      period: "this_month"
    )
    refute Notification.exists?(own.id)

    delete account_notification_path(foreign)
    assert_response :not_found
    assert Notification.exists?(foreign.id)
  end

  test "deleting the only notification on the last page returns to the preceding valid page" do
    notifications = 51.times.map do |index|
      @user.notifications.create!(
        notification_type: "system.notice",
        title: "LAST-PAGE-#{index}",
        created_at: 51.minutes.ago + index.minutes
      )
    end
    only_last_page_item = notifications.first

    delete account_notification_path(only_last_page_item), params: {
      category: "system",
      type: "system.notice",
      page: "2"
    }

    assert_redirected_to account_notifications_path(
      category: "system",
      type: "system.notice"
    )
    refute Notification.exists?(only_last_page_item.id)
    assert_equal 50, @user.notifications.where(notification_type: "system.notice").count
  end

  test "notification API deletion requires a writer bound to the owner" do
    notification = @user.notifications.create!(
      notification_type: "system.notice",
      title: "API deletable notification"
    )
    _reader_key, reader_token = Administration::ApiKey.generate!(
      name: "notification-reader-#{SecureRandom.hex(4)}",
      scopes: %w[read],
      user: @user
    )

    delete "/api/v1/notifications/#{notification.id}",
      headers: { "Authorization" => "Bearer #{reader_token}" }
    assert_response :forbidden
    assert Notification.exists?(notification.id)

    _foreign_key, foreign_token = Administration::ApiKey.generate!(
      name: "notification-foreign-writer-#{SecureRandom.hex(4)}",
      scopes: %w[write],
      user: @author
    )
    delete "/api/v1/notifications/#{notification.id}",
      headers: { "Authorization" => "Bearer #{foreign_token}" }
    assert_response :not_found
    assert Notification.exists?(notification.id)

    _writer_key, writer_token = Administration::ApiKey.generate!(
      name: "notification-owner-writer-#{SecureRandom.hex(4)}",
      scopes: %w[write],
      user: @user
    )
    delete "/api/v1/notifications/#{notification.id}",
      headers: { "Authorization" => "Bearer #{writer_token}" }
    assert_response :no_content
    refute Notification.exists?(notification.id)
  end

  private

  def inertia_headers
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version,
      "X-McWeb-Application" => "account",
      "HTTP_REFERER" => "http://www.example.com/app/account"
    }
  end
end
