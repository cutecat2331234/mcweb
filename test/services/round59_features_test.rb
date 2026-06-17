# frozen_string_literal: true

require "test_helper"

class Round59FeaturesTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user
    grant_permission(@admin, "store.orders.refund")
  end

  test "partial refund restores proportional store credit" do
    @user.update!(store_credit_cents: 0)
    order = Commerce::Order.create!(
      public_id: "ord_r59_#{SecureRandom.hex(4)}",
      order_number: "R59#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 700,
      store_credit_amount_cents: 300,
      currency: "CNY"
    )
    payment = Payments::Record.create!(
      order: order,
      provider: "fake",
      status: "succeeded",
      amount_cents: 700,
      currency: "CNY",
      provider_payment_id: "r59_pay_#{SecureRandom.hex(4)}"
    )
    Commerce::StoreCreditTransaction.create!(
      user: @user,
      order: order,
      amount_cents: -300,
      note: "抵扣"
    )

    result = Commerce::ProcessRefund.call(
      order: order,
      payment_record: payment,
      amount_cents: 350,
      reason: "Partial",
      approved_by: @admin
    )
    assert result.success?
    assert_equal 150, @user.reload.store_credit_cents
    assert_equal 150, order.reload.store_credit_restored_cents
  end

  test "restore store credit partial service" do
    order = Commerce::Order.create!(
      public_id: "ord_r59p_#{SecureRandom.hex(4)}",
      order_number: "R59P#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 500,
      store_credit_amount_cents: 500,
      store_credit_restored_cents: 0,
      currency: "CNY"
    )

    result = Commerce::RestoreStoreCreditPartial.call(
      order: order,
      refund_amount_cents: 250,
      payment_amount_cents: 500
    )
    assert result.success?
    assert_equal 250, result.value[:restored_cents]
    assert_equal 250, @user.reload.store_credit_cents
  end

  test "subscribe product availability alert for upcoming product" do
    product = Commerce::Product.create!(
      name: "Upcoming R59",
      slug: "r59-up-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      available_at: 2.days.from_now
    )

    result = Commerce::SubscribeProductAvailabilityAlert.call(user: @user, product: product)
    assert result.success?
    assert Commerce::ProductAvailabilityAlert.exists?(user: @user, product: product)
  end

  test "reject availability alert for already available product" do
    product = Commerce::Product.create!(
      name: "Available R59",
      slug: "r59-av-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1
    )

    result = Commerce::SubscribeProductAvailabilityAlert.call(user: @user, product: product)
    assert result.failure?
  end

  test "notify product available job" do
    product = Commerce::Product.create!(
      name: "Launch R59",
      slug: "r59-launch-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      public_id: "pub_r59_#{SecureRandom.hex(4)}"
    )
    Commerce::ProductAvailabilityAlert.create!(user: @user, product: product)

    assert_difference -> { Notification.where(user: @user, notification_type: "commerce.product_available").count }, 1 do
      Commerce::NotifyProductAvailableJob.perform_now(product.id)
    end
  end

  test "tag group color_hex" do
    group = Community::TagGroup.create!(
      name: "Colored",
      slug: "r59-colored-#{SecureRandom.hex(3)}",
      color_hex: "#ff5500"
    )
    assert_equal "#ff5500", group.color_hex
  end

  test "tag color on forum tag model" do
    tag = Community::Tag.create!(name: "Blue Tag", slug: "r59-blue-#{SecureRandom.hex(3)}", color_hex: "#2563eb")
    assert_equal "#2563eb", tag.color_hex
    assert_equal "#2563eb", tag.effective_tag.color_hex
  end
end

class Round59SearchAssigneeTest < ActionDispatch::IntegrationTest
  test "search accepts assignee filter param" do
    user = create_user
    assignee = create_user
    category = Community::Category.find_or_create_by!(slug: "r59-sc-#{SecureRandom.hex(4)}") { |c| c.name = "SC" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r59-ss-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    topic = Community::Topic.create!(title: "Assigned topic", user: user, section: section, status: :published, assigned_to: assignee)

    sign_in_as(assignee)
    get forum_search_path, params: { q: "Assigned", assignee: "me" }
    assert_response :success
    page = JSON.parse(response.body.match(/data-page="app" type="application\/json">(.+?)<\/script>/m)[1])
    topic_titles = page.dig("props", "topics").map { |t| t["title"] }
    assert_includes topic_titles, topic.title
  end
end

class Round59UserProfileWalletTest < ActionDispatch::IntegrationTest
  test "profile shows store credit for self" do
    user = create_user
    user.update!(store_credit_cents: 1200)

    sign_in_as(user)
    get forum_user_path(user.username)
    assert_response :success
    assert_includes response.body, "store_credit_label"
    assert_includes response.body, "store_wallet_url"
  end
end
