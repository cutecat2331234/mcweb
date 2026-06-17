# frozen_string_literal: true

require "test_helper"

class Commerce::EnsureProductDiscussionTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r31-discuss") { |c| c.name = "R31 Discuss" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r31-discuss-sec") do |s|
      s.name = "Product Discuss"
      s.position = 0
    end
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Discussion Product",
      slug: "discuss-r31-#{SecureRandom.hex(4)}",
      price_cents: 1000,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
  end

  test "creates forum topic and links product" do
    result = Commerce::EnsureProductDiscussionTopic.call(product: @product, creator: @user)
    assert result.success?
    @product.reload
    assert @product.forum_topic_id.present?
    assert_equal "[商品] #{@product.name}", @product.forum_topic.title
  end

  test "returns existing topic without duplicate" do
    first = Commerce::EnsureProductDiscussionTopic.call(product: @product, creator: @user)
    assert first.success?

    assert_no_difference -> { Community::Topic.count } do
      second = Commerce::EnsureProductDiscussionTopic.call(product: @product, creator: @user)
      assert second.success?
      assert_equal first.value.id, second.value.id
    end
  end
end

class Commerce::ShareReviewToForumTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r31-review") { |c| c.name = "R31 Review" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r31-review-sec") do |s|
      s.name = "Review Sec"
      s.position = 0
    end
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Review Product",
      slug: "review-r31-#{SecureRandom.hex(4)}",
      price_cents: 500,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @review = Commerce::Review.create!(
      user: @user,
      product: @product,
      rating: 5,
      body: "Great product!",
      status: "published"
    )
  end

  test "shares review to forum" do
    result = Commerce::ShareReviewToForum.call(user: @user, review: @review)
    assert result.success?, result.error || result.errors.inspect
    @review.reload
    assert @review.forum_post_id.present?
    assert_includes @review.forum_post.body, "Great product"
    assert_includes @review.forum_post.body, "/app/store/products/"
  end

  test "cannot share another users review" do
    other = create_user
    result = Commerce::ShareReviewToForum.call(user: other, review: @review)
    assert result.failure?
  end

  test "cannot share twice" do
    Commerce::ShareReviewToForum.call(user: @user, review: @review)
    result = Commerce::ShareReviewToForum.call(user: @user, review: @review.reload)
    assert result.failure?
  end
end

class Community::BumpCooldownTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r31-bump") { |c| c.name = "R31 Bump" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r31-bump-sec") do |s|
      s.name = "Bump Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @mod,
      title: "Bump cooldown",
      status: "published",
      last_posted_at: 2.days.ago,
      last_post_user: @mod,
      bumped_at: 1.hour.ago
    )
    SiteSetting.set("forum.bump_cooldown_hours", "24")
  end

  test "rejects bump during cooldown" do
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "bump")
    assert result.failure?
    assert_includes result.error, "冷却"
  end

  test "allows bump after cooldown" do
    @topic.update!(bumped_at: 25.hours.ago)
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "bump")
    assert result.success?
    assert @topic.reload.bumped_at > 1.minute.ago
  end
end

class Community::NotifyPostEditedTest < ActiveSupport::TestCase
  setup do
    @author = create_user(username: "author_r31")
    @subscriber = create_user(username: "sub_r31")
    category = Community::Category.find_or_create_by!(slug: "r31-edit") { |c| c.name = "R31 Edit" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r31-edit-sec") do |s|
      s.name = "Edit Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @author, section: section, title: "Edit notify", body: "Original OP").value
    @post = @topic.posts.first
    Community::Subscription.create!(user: @subscriber, subscribable: @topic)
    NotificationPreference.set!(@subscriber, channel: "in_app", notification_type: "forum.post_edited", enabled: true)
  end

  test "notifies subscribers when post edited" do
    assert_difference -> { Notification.where(user: @subscriber, notification_type: "forum.post_edited").count }, 1 do
      Community::NotifyPostEdited.call(post: @post)
    end
  end

  test "edit post triggers notification" do
    assert_difference -> { Notification.where(user: @subscriber, notification_type: "forum.post_edited").count }, 1 do
      result = Community::EditPost.call(user: @author, post: @post, body: "Updated body text")
      assert result.success?
    end
  end
end

class Commerce::ProductQuestionOrderItemTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Question Product",
      slug: "question-r31-#{SecureRandom.hex(4)}",
      price_cents: 200,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 200,
      total_cents: 200
    )
    @order_item = Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 200,
      quantity: 1,
      total_cents: 200,
      fulfillment_snapshot: {}
    )
  end

  test "creates question linked to order item" do
    result = Commerce::CreateProductQuestion.call(
      user: @user,
      product: @product,
      body: "How do I download?",
      order_item: @order_item
    )
    assert result.success?
    assert_equal @order_item.id, result.value.store_order_item_id
  end

  test "rejects mismatched order item" do
    other_product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Other",
      slug: "other-r31-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    result = Commerce::CreateProductQuestion.call(
      user: @user,
      product: other_product,
      body: "Wrong product",
      order_item: @order_item
    )
    assert result.failure?
  end
end

class Commerce::NotifyProductChangelogJobTest < ActiveSupport::TestCase
  setup do
    @buyer = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Changelog Product",
      slug: "changelog-r31-#{SecureRandom.hex(4)}",
      price_cents: 300,
      currency: "CNY",
      status: "active",
      product_type: "digital",
      changelog: "v2.0: new features",
      version: "2.0"
    )
    order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @buyer,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 300,
      total_cents: 300
    )
    Commerce::OrderItem.create!(
      order: order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 300,
      quantity: 1,
      total_cents: 300,
      fulfillment_snapshot: {}
    )
    NotificationPreference.set!(@buyer, channel: "in_app", notification_type: "commerce.product_changelog", enabled: true)
  end

  test "notifies buyers and records version" do
    assert_difference -> { Notification.where(user: @buyer, notification_type: "commerce.product_changelog").count }, 1 do
      Commerce::NotifyProductChangelogJob.perform_now(@product.id)
    end
    assert_equal "2.0", @product.reload.changelog_notified_version
  end

  test "skips duplicate notification for same version" do
    Commerce::NotifyProductChangelogJob.perform_now(@product.id)
    assert_no_difference -> { Notification.where(notification_type: "commerce.product_changelog").count } do
      Commerce::NotifyProductChangelogJob.perform_now(@product.id)
    end
  end
end

class Commerce::PublicCouponTest < ActiveSupport::TestCase
  setup do
    @coupon = Commerce::Coupon.create!(
      code: "R31SAVE",
      discount_type: "percentage",
      discount_value: 10,
      active: true,
      min_amount_cents: 0
    )
  end

  test "active coupon lookup" do
    found = Commerce::Coupon.active_coupons.find_by(code: "R31SAVE")
    assert_equal @coupon.id, found.id
  end
end

class Community::LinkedProductTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r31-link") { |c| c.name = "R31 Link" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r31-link-sec") do |s|
      s.name = "Link Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Linked", body: "OP").value
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Linked Product",
      slug: "linked-r31-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital",
      forum_topic: @topic
    )
  end

  test "topic has linked product" do
    assert_equal @product.id, @topic.reload.linked_product.id
  end
end
