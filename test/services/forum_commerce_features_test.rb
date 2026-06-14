# frozen_string_literal: true

require "test_helper"

class Community::CreateTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @category = Community::Category.find_or_create_by!(slug: "topic-test") { |c| c.name = "Topic Test" }
    @section = Community::Section.find_or_create_by!(category: @category, slug: "topic-general") do |s|
      s.name = "General"
      s.position = 0
    end
  end

  test "creates topic with opening post" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "New topic",
      body: "Opening content here.",
      ip_address: "127.0.0.1"
    )

    assert result.success?
    topic = result.value
    assert_equal 1, topic.posts.count
    assert_equal "Opening content here.", topic.posts.first.body
    assert_equal 0, topic.replies_count
    assert Community::Subscription.exists?(user: @user, subscribable: topic)
  end
end

class Community::ToggleReactionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @other = create_user(email: "other@example.com", username: "otheruser")
    @category = Community::Category.find_or_create_by!(slug: "react-cat") { |c| c.name = "React" }
    @section = Community::Section.find_or_create_by!(category: @category, slug: "react-sec") do |s|
      s.name = "React Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "React topic",
      body: "First post",
      ip_address: "127.0.0.1"
    ).value
    @post = @topic.posts.first
  end

  test "toggles reaction on post" do
    add = Community::ToggleReaction.call(user: @other, post: @post, emoji: "👍")
    assert add.success?
    assert add.value[:added]

    remove = Community::ToggleReaction.call(user: @other, post: @post, emoji: "👍")
    assert remove.success?
    assert_not remove.value[:added]
  end
end

class Community::EditPostTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @category = Community::Category.find_or_create_by!(slug: "edit-cat") { |c| c.name = "Edit" }
    @section = Community::Section.find_or_create_by!(category: @category, slug: "edit-sec") do |s|
      s.name = "Edit Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Edit topic",
      body: "Original body",
      ip_address: "127.0.0.1"
    ).value
    @post = @topic.posts.first
  end

  test "author can edit within window" do
    result = Community::EditPost.call(user: @user, post: @post, body: "Updated body")
    assert result.success?
    assert_equal "Updated body", @post.reload.body
    assert @post.edited_at.present?
  end
end

class Community::NotifyTopicReplyTest < ActiveSupport::TestCase
  test "notifies topic subscribers on reply" do
    author = create_user
    subscriber = create_user(email: "sub@example.com", username: "subuser")
    category = Community::Category.find_or_create_by!(slug: "notify-cat") { |c| c.name = "Notify" }
    section = Community::Section.find_or_create_by!(category: category, slug: "notify-sec") do |s|
      s.name = "Notify Sec"
      s.position = 0
    end
    topic = Community::CreateTopic.call(
      user: author,
      section: section,
      title: "Notify topic",
      body: "Opening",
      ip_address: "127.0.0.1"
    ).value
    Community::Subscription.subscribe!(subscriber, topic)

    replier = create_user(email: "reply@example.com", username: "replier")
    post = Community::CreatePost.call(
      user: replier,
      topic: topic,
      body: "A reply",
      ip_address: "127.0.0.1"
    ).value

    assert post.persisted?
    assert Notification.exists?(user: subscriber, notification_type: "forum.topic_reply")
    assert_not Notification.exists?(user: replier, notification_type: "forum.topic_reply")
  end
end

class Community::MoveTopicTest < ActiveSupport::TestCase
  test "moves topic when authorized" do
    user = create_user
    grant_permission(user, "forum.topics.move")
    category = Community::Category.find_or_create_by!(slug: "move-cat") { |c| c.name = "Move" }
    section_a = Community::Section.find_or_create_by!(category: category, slug: "move-a") do |s|
      s.name = "A"
      s.position = 0
    end
    section_b = Community::Section.create!(category: category, name: "B", slug: "move-b", position: 1)
    topic = Community::CreateTopic.call(
      user: user,
      section: section_a,
      title: "Move me",
      body: "Content",
      ip_address: "127.0.0.1"
    ).value

    result = Community::MoveTopic.call(user: user, topic: topic, section: section_b)
    assert result.success?
    assert_equal section_b.id, topic.reload.forum_section_id
  end
end

class Commerce::PreviewCouponTest < ActiveSupport::TestCase
  test "previews percentage coupon" do
    Commerce::Coupon.create!(
      code: "OFF10",
      discount_type: "percentage",
      discount_value: 10,
      active: true
    )

    result = Commerce::PreviewCoupon.call(subtotal_cents: 1000, code: "OFF10")
    assert result.success?
    assert_equal 100, result.value[:discount_cents]
    assert_equal 900, result.value[:total_cents]
  end
end

class Commerce::ValidateCartItemTest < ActiveSupport::TestCase
  test "rejects insufficient stock" do
    user = create_user
    product = Commerce::Product.create!(
      public_id: "prod_stock1",
      name: "Limited",
      slug: "limited-item",
      product_type: "currency",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 1
    )

    result = Commerce::ValidateCartItem.call(user: user, product: product, quantity: 2)
    assert result.failure?
    assert_match(/stock/i, result.error)
  end
end

class Commerce::MergeGuestCartTest < ActiveSupport::TestCase
  test "merges guest cart into user cart" do
    user = create_user
    product = Commerce::Product.find_or_create_by!(slug: "merge-item") do |p|
      p.public_id = "prod_merge1"
      p.name = "Merge Item"
      p.product_type = "currency"
      p.status = "active"
      p.price_cents = 500
      p.currency = "CNY"
    end

    guest_cart = Commerce::Cart.create!
    guest_cart.add_item!(product: product, quantity: 1)

    result = Commerce::MergeGuestCart.call(user: user, session_token: guest_cart.session_token)
    assert result.success?
    assert result.value[:merged]

    user_cart = Commerce::Cart.find_by!(user: user)
    assert_equal 1, user_cart.items.count
    assert_nil Commerce::Cart.find_by(id: guest_cart.id)
  end
end
