# frozen_string_literal: true

require "test_helper"

class Community::PreviewCensoredWordsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
    Community::CensoredWord.find_or_create_by!(word: "badword") { |w| w.replacement = "***" }
  end

  test "preview applies censored words" do
    Rails.cache.delete("forum/censored_words")
    post forum_preview_path, params: { body: "hello badword world" }, as: :json
    assert_response :success
    assert_not_includes response.parsed_body["html"], "badword"
  end
end

class Community::EditTopicPrefixTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r23-cat") { |c| c.name = "R23" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r23-sec") do |s|
      s.name = "R23 Sec"
      s.position = 0
      s.prefixes = %w[公告]
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Prefix topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user
    )
  end

  test "updates prefix" do
    result = Community::EditTopic.call(user: @user, topic: @topic, prefix: "公告")
    assert result.success?
    assert_equal "公告", @topic.reload.prefix
  end
end

class Commerce::CreateReviewPhotosTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_rp_#{SecureRandom.hex(4)}",
      name: "Review photos",
      slug: "review-photos-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    Commerce::Order.create!(
      user: @user,
      order_number: "ORD-RP-#{SecureRandom.hex(4)}",
      status: "paid",
      subtotal_cents: 100,
      discount_cents: 0,
      total_cents: 100,
      currency: "CNY"
    ).tap do |order|
      Commerce::OrderItem.create!(
        order: order,
        product: @product,
        product_name: @product.name,
        unit_price_cents: 100,
        quantity: 1,
        total_cents: 100
      )
    end
    Commerce::Review.create!(
      user: @user,
      product: @product,
      rating: 5,
      body: "Great",
      status: "published"
    )
  end

  test "edit without photos keeps existing attachments" do
    review = Commerce::Review.find_by!(user: @user, product: @product)
    review.photos.attach(
      io: StringIO.new("fake"),
      filename: "test.jpg",
      content_type: "image/jpeg"
    )
    result = Commerce::CreateReview.call(user: @user, product: @product, rating: 4, body: "Updated")
    assert result.success?
    assert review.reload.photos.attached?
  end
end

class Commerce::CompareCountTest < ActiveSupport::TestCase
  test "counts only available products" do
    product = Commerce::Product.create!(
      public_id: "prod_cc_#{SecureRandom.hex(4)}",
      name: "Compare count",
      slug: "compare-count-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    archived = Commerce::Product.create!(
      public_id: "prod_arch_#{SecureRandom.hex(4)}",
      name: "Archived",
      slug: "archived-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "archived",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    session = { compare_product_ids: [ product.public_id, archived.public_id ] }
    count = Commerce::Product.available.where(public_id: session[:compare_product_ids]).count
    assert_equal 1, count
  end
end

class Commerce::NotifyOrderEventTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.order_created", enabled: true)
  end

  test "creates in-app notification" do
    assert_difference -> { Notification.where(notification_type: "commerce.order_created").count }, 1 do
      Commerce::NotifyOrderEvent.call(
        user: @user,
        notification_type: "commerce.order_created",
        title: "订单已创建",
        body: "测试订单",
        path: "/store/orders/test"
      )
    end
  end
end
