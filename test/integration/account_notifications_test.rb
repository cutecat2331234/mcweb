# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class AccountNotificationsTest < ActionDispatch::IntegrationTest
  include InertiaRails::Minitest

  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "canonical notification center is private and remains available when forum is disabled" do
    SiteSetting.set("features.forum.enabled", "false")
    @user.notifications.create!(notification_type: "system.notice", title: "Account notice")

    get account_notifications_path, headers: inertia_headers

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "Account/Notifications/Index", inertia.component
    assert_inertia_deferred_props :notifications, group: "portal_navigation"

    inertia_load_deferred_props("portal_navigation")
    navigation = inertia.props.deep_symbolize_keys.fetch(:notifications)
    assert_equal 1, navigation.fetch(:unread_count)
    assert_equal account_notifications_path, navigation.fetch(:url)
  end

  test "canonical list classifies forum commerce and fail-safe system notifications" do
    %w[
      forum.mention
      commerce.order_created
      system.notice
      chat.safety.appeal_accepted
      pvp.test_completed
      plugin.release_ready
    ].each do |type|
      metadata = type == "pvp.test_completed" ? { topic: "downstream-resource-id" } : {}
      @user.notifications.create!(notification_type: type, title: type, metadata:)
    end

    get account_notifications_path, headers: inertia_headers

    rows = notification_items
    categories = rows.to_h { |row| [ row.fetch(:notification_type), row.fetch(:category) ] }
    assert_equal "forum", categories.fetch("forum.mention")
    assert_equal "commerce", categories.fetch("commerce.order_created")
    assert_equal "system", categories.fetch("system.notice")
    assert_equal "system", categories.fetch("chat.safety.appeal_accepted")
    assert_equal "system", categories.fetch("pvp.test_completed")
    assert_equal "system", categories.fetch("plugin.release_ready")
    assert_equal "pvp.test_completed",
      rows.find { |row| row.fetch(:notification_type) == "pvp.test_completed" }.fetch(:title)

    get account_notifications_path(category: "system"), headers: inertia_headers
    system_types = notification_items.pluck(:notification_type)
    assert_equal %w[
      chat.safety.appeal_accepted
      plugin.release_ready
      pvp.test_completed
      system.notice
    ], system_types.sort
  end

  test "mark all read fails closed when an explicit filter is invalid" do
    notification = @user.notifications.create!(
      notification_type: "system.notice",
      title: "Keep unread"
    )

    patch mark_all_read_account_notifications_path(category: "unregistered-domain")

    assert_redirected_to account_notifications_path
    assert_nil notification.reload.read_at
    assert_equal I18n.t("mcweb.flash.notification_filters_invalid"), flash[:alert]
  end

  test "non-object notification metadata cannot break the list or escape on visit" do
    notification = @user.notifications.create!(
      notification_type: "plugin.malformed_payload",
      title: "Malformed metadata remains visible",
      metadata: []
    )

    get account_notifications_path, headers: inertia_headers

    assert_response :success
    assert_includes response.body, "Malformed metadata remains visible"

    get visit_account_notification_path(notification)

    assert_redirected_to account_notifications_path
    assert notification.reload.read?
  end

  test "legacy forum GET redirects to canonical path and preserves only valid filters" do
    SiteSetting.set("features.forum.enabled", "false")

    get forum_notifications_path(
      category: "system",
      read: "unread",
      type: "chat.safety.appeal_accepted",
      period: "today",
      page: "2",
      unsafe: "discarded"
    )

    assert_redirected_to account_notifications_path(
      category: "system",
      read: "unread",
      type: "chat.safety.appeal_accepted",
      period: "today",
      page: 2
    )

    get forum_notifications_path(
      category: "pvp",
      read: "all",
      type: "../../unsafe",
      period: "forever",
      page: "-1"
    )
    assert_redirected_to account_notifications_path
  end

  test "legacy mutation routes complete on the canonical notification center" do
    notification = @user.notifications.create!(
      notification_type: "forum.mention",
      title: "Legacy action"
    )

    patch mark_read_forum_notification_path(notification, category: "forum", read: "unread")

    assert_redirected_to account_notifications_path(category: "forum", read: "unread")
    assert notification.reload.read?
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "unsafe notification destinations fall back to the canonical center" do
    notification = @user.notifications.create!(
      notification_type: "system.notice",
      title: "Unsafe destination",
      metadata: { path: "//example.invalid/escape" }
    )

    get visit_account_notification_path(notification)

    assert_redirected_to account_notifications_path
    assert notification.reload.read?
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  private

  def notification_items
    inertia.props.deep_symbolize_keys
      .fetch(:notificationGroups)
      .flat_map { |group| group.fetch(:items) }
  end

  def inertia_headers
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version
    }
  end
end
