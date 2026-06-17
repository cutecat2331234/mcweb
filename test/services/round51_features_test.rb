# frozen_string_literal: true

require "test_helper"

class Community::PostPermalinkTest < ActiveSupport::TestCase
  test "path uses floor anchor" do
    user = create_user
    category = Community::Category.find_or_create_by!(slug: "r51-perm") { |c| c.name = "P" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r51-perm-sec") { |s| s.name = "S"; s.position = 0 }
    topic = Community::CreateTopic.call(user: user, section: section, title: "Perm", body: "OP", ip_address: "127.0.0.1").value
    post = topic.posts.first

    assert_equal "/app/forum/topics/#{topic.public_id}#p-#{post.floor_number}", Community::PostPermalink.path(topic, post)
  end
end

class Community::GroupMentionTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @staff = create_user
    grant_permission(@staff, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r51-mention") { |c| c.name = "M" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r51-mention-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Mentions", body: "OP", ip_address: "127.0.0.1").value
    @post = @topic.posts.first
  end

  test "@staff notifies moderators" do
    assert_difference -> { Notification.where(user: @staff, notification_type: "forum.mention").count }, 1 do
      Community::ProcessMentions.call(body: "Hey @staff please review", author: @author, post: @post, topic: @topic)
    end
  end
end

class Community::SolvedMineFilterTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @other = create_user
    category = Community::Category.find_or_create_by!(slug: "r51-solved") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r51-solved-sec") { |s| s.name = "S"; s.position = 0 }
    @mine = Community::CreateTopic.call(user: @user, section: @section, title: "Mine", body: "OP", ip_address: "127.0.0.1").value
    @theirs = Community::CreateTopic.call(user: @other, section: @section, title: "Theirs", body: "OP", ip_address: "127.0.0.1").value
    Community::MarkTopicSolved.call(user: @user, topic: @mine, post: @mine.posts.first)
    Community::MarkTopicSolved.call(user: @other, topic: @theirs, post: @theirs.posts.first)
    @helper = Class.new { include Community::TopicFilterable }.new
    @scope = Community::Topic.where(status: :published)
  end

  test "solved_mine returns only current user solved topics" do
    ids = @helper.send(:apply_topic_filter, @scope, filter: "solved_mine", user: @user).pluck(:id)
    assert_includes ids, @mine.id
    assert_not_includes ids, @theirs.id
  end
end

class Community::ArchiveTopicTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "r51-archive") { |c| c.name = "A" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r51-archive-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Archive me", body: "OP", ip_address: "127.0.0.1").value
  end

  test "archive excludes topic from published_listed" do
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "archive")
    assert result.success?
    assert_not_includes Community::Topic.published_listed.pluck(:id), @topic.id
  end

  test "archived topic hidden from regular users" do
    Community::ModerateTopic.call(user: @mod, topic: @topic, action: "archive")
    helper = Class.new { include Community::TopicVisibility }.new
    refute helper.send(:topic_visible?, @topic.reload, user: create_user)
    assert helper.send(:topic_visible?, @topic, user: @author)
    assert helper.send(:topic_visible?, @topic, user: @mod)
  end
end

class Community::DigestWatchedOnlyTest < ActiveSupport::TestCase
  setup do
    @user = create_user(forum_digest_frequency: "daily", forum_digest_watched_only: true)
    category = Community::Category.find_or_create_by!(slug: "r51-digest") { |c| c.name = "D" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r51-digest-sec") { |s| s.name = "S"; s.position = 0 }
    @watched_topic = Community::CreateTopic.call(user: @user, section: @section, title: "Watched", body: "OP", ip_address: "127.0.0.1").value
    @user.notifications.create!(
      notification_type: "forum.topic_reply",
      title: "Watched reply",
      body: "On watched topic",
      metadata: { topic_id: @watched_topic.public_id }
    )
    @user.notifications.create!(
      notification_type: "forum.topic_reply",
      title: "Other reply",
      body: "On other topic",
      metadata: { topic_id: "topic_nonexistent" }
    )
  end

  test "watched only digest skips when no subscriptions" do
    Community::Subscription.where(user: @user).destroy_all
    @user.update!(forum_digest_watched_only: true)
    result = Community::SendForumDigest.call(user: @user)
    assert result.success?
    assert result.value[:skipped]
  end

  test "watched only digest includes watched topic notifications" do
    result = Community::SendForumDigest.call(user: @user)
    assert result.success?
    assert result.value[:sent]
    assert_equal 1, result.value[:count]
  end
end

class Commerce::MinCheckoutTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    SiteSetting.set("store.min_checkout_subtotal_cents", "5000")
    @product = Commerce::Product.create!(
      name: "Cheap", slug: "cheap-#{SecureRandom.hex(4)}", public_id: "p_#{SecureRandom.hex(8)}",
      price_cents: 1000, currency: "CNY", product_type: "virtual", status: "active"
    )
    @cart = Commerce::Cart.create!(user: @user)
    @cart.add_item!(product: @product, quantity: 1)
  end

  teardown do
    SiteSetting.set("store.min_checkout_subtotal_cents", "0")
  end

  test "create order rejects below minimum subtotal" do
    result = Commerce::CreateOrder.call(cart: @cart, user: @user)
    assert result.failure?
    assert_includes result.error, "最低消费"
  end
end

class Commerce::AbandonedCartSecondReminderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.abandoned_cart", enabled: true)
    @product = Commerce::Product.create!(
      public_id: "prod_2nd_#{SecureRandom.hex(4)}",
      name: "Second",
      slug: "second-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @cart = Commerce::Cart.create!(user: @user)
    @cart.add_item!(product: @product, quantity: 1)
    @cart.update_columns(
      updated_at: 4.days.ago,
      abandoned_reminder_sent_at: 4.days.ago
    )
  end

  test "second reminder sent after first reminder window" do
    assert_nil @cart.abandoned_second_reminder_sent_at
    assert_enqueued_with(job: MailDeliveryJob) do
      Commerce::AbandonedCartReminderJob.perform_now
    end
    assert @cart.reload.abandoned_second_reminder_sent_at.present?
  end
end

class Commerce::DispatchOrderWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_wh_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  teardown do
    SiteSetting.set("store.order_webhook_url", "")
  end

  test "queues webhook when url configured" do
    SiteSetting.set("store.order_webhook_url", "https://example.com/hooks/orders")
    assert_enqueued_with(job: Commerce::DispatchOrderWebhookJob) do
      Commerce::DispatchOrderWebhook.call(order: @order, event_type: "order.status_changed", from_status: "pending", to_status: "paid")
    end
  end

  test "skips when url blank" do
    result = Commerce::DispatchOrderWebhook.call(order: @order, event_type: "order.created")
    assert result.success?
    assert result.value[:skipped]
  end
end

class Commerce::NotifyOrderStatusChangeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.order_fulfilled", enabled: true)
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.order_fulfilled", enabled: false)
    @order = Commerce::Order.create!(
      public_id: "ord_notify_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "processing",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  test "notifies user on status change to fulfilled" do
    @order.update!(status: "fulfilled")
    assert_difference -> { Notification.where(user: @user, notification_type: "commerce.order_fulfilled").count }, 1 do
      Commerce::NotifyOrderStatusChange.call(order: @order, from_status: "processing")
    end
  end
end
