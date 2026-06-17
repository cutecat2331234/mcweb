# frozen_string_literal: true

require "test_helper"

class Community::RestorePostTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r37-restore") { |c| c.name = "R37 Restore" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r37-restore-sec") { |s| s.name = "Restore"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Restore test", body: "OP", ip_address: "127.0.0.1").value
    @post = @topic.posts.first
    @post.soft_delete!
  end

  test "moderator can restore deleted post" do
    post = Community::Post.with_discarded.find(@post.id)
    assert post.deleted_at.present?, "post should be soft-deleted"
    result = Community::RestorePost.call(actor: @mod, post: post)
    assert result.success?, result.error.to_s
    assert_nil post.reload.deleted_at
  end
end

class Community::EnforceWarningThresholdTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    SiteSetting.set("forum.warning_mute_threshold", "5")
    SiteSetting.set("forum.warning_mute_days", "3")
    @mod = create_user
    grant_permission(@mod, "forum.users.warn")
  end

  test "auto mutes user when warning threshold reached" do
    Community::CreateUserWarning.call(actor: @mod, user: @user, reason: "Spam", points: 5)
    assert Community::Mute.muted?(@user)
  end
end

class Community::CreateStaffNoteTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.users.warn")
    @user = create_user
  end

  test "staff can add private note" do
    result = Community::CreateStaffNote.call(actor: @mod, user: @user, body: "Watch this user")
    assert result.success?
    assert_equal 1, @user.forum_staff_notes.count
  end
end

class Community::FetchGiftCardOneboxTest < ActiveSupport::TestCase
  setup do
    @card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(8).upcase}",
      balance_cents: 500,
      initial_balance_cents: 500,
      currency: "CNY",
      active: true
    )
  end

  test "fetch gift card onebox does not expose card details" do
    result = Community::FetchGiftCardOnebox.call(url: "/app/store/gift_cards/#{@card.code}")
    assert result.success?
    assert_nil result.value
  end

  test "format post body does not embed gift card onebox" do
    result = Community::FormatPostBody.call(body: "/app/store/gift_cards/#{@card.code}")
    assert result.success?
    assert_not_includes result.value, "gift-card-onebox"
    assert_includes result.value, @card.code
  end
end

class Commerce::RestoreGiftCardBalanceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_r37_#{SecureRandom.hex(4)}",
      name: "R37 Product",
      slug: "r37-prod-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 5
    )
    @gift_card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(10).upcase}",
      balance_cents: 200,
      initial_balance_cents: 500,
      currency: "CNY",
      active: true,
      created_by: @user
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user, gift_card_code: @gift_card.code).value
    Commerce::DebitGiftCard.call(order: @order)
  end

  test "restores gift card balance on full refund path" do
    Commerce::RestoreGiftCardBalance.call(order: @order)
    assert_equal 200, @gift_card.reload.balance_cents
    assert @gift_card.active?
  end

  test "fails when gift card association is missing" do
    @order.update_columns(store_gift_card_id: nil)

    result = Commerce::RestoreGiftCardBalance.call(order: @order.reload)
    assert result.failure?
    assert_equal "礼品卡信息无效。", result.error
  end
end

class Commerce::RestoreGiftCardPartialTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @gift_card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(10).upcase}",
      balance_cents: 0,
      initial_balance_cents: 500,
      currency: "CNY",
      active: true,
      created_by: @user
    )
    @order = Commerce::Order.create!(
      public_id: "ord_r37p_#{SecureRandom.hex(4)}",
      order_number: "R37P#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 500,
      total_cents: 300,
      gift_card: @gift_card,
      gift_card_amount_cents: 200,
      currency: "CNY"
    )
  end

  test "fails when gift card association is missing" do
    @order.update_columns(store_gift_card_id: nil)

    result = Commerce::RestoreGiftCardPartial.call(
      order: @order.reload,
      refund_amount_cents: 150,
      payment_amount_cents: 300
    )
    assert result.failure?
    assert_equal "礼品卡信息无效。", result.error
  end
end

class Commerce::ZeroTotalCheckoutTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_zero_#{SecureRandom.hex(4)}",
      name: "Zero Product",
      slug: "zero-prod-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @gift_card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(10).upcase}",
      balance_cents: 200,
      initial_balance_cents: 200,
      currency: "CNY",
      active: true,
      created_by: @user
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user, gift_card_code: @gift_card.code).value
  end

  test "gift card covers full order amount" do
    assert_equal 0, @order.total_cents
    assert_equal 100, @order.gift_card_amount_cents
  end

  test "zero total order can complete free checkout payment" do
    payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      amount_cents: 0,
      currency: "CNY",
      status: "pending"
    )

    result = Commerce::ConfirmPayment.call(payment_record: payment, provider_payment_id: "free-#{@order.public_id}")
    assert result.success?
    assert_equal "paid", @order.reload.status
    assert_equal "succeeded", payment.reload.status
    assert_equal 100, @gift_card.reload.balance_cents
  end
end

class Community::SectionTopicTemplateTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r37-template") { |c| c.name = "R37 Template" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r37-template-sec") do |s|
      s.name = "Template Sec"
      s.position = 0
      s.topic_template = "请填写以下信息：\n1. 版本\n2. 问题描述"
    end
    @section.update!(topic_template: "请填写以下信息：\n1. 版本\n2. 问题描述")
  end

  test "section has topic template" do
    assert_includes @section.topic_template, "版本"
  end
end

class Community::SearchDateFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r37-search") { |c| c.name = "R37 Search" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r37-search-sec") { |s| s.name = "Search"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Date filter topic unique", body: "Body", ip_address: "127.0.0.1").value
  end

  test "search with date range returns results" do
    get forum_search_path, params: {
      q: "Date filter topic unique",
      created_after: 1.day.ago.strftime("%Y-%m-%d"),
      created_before: 1.day.from_now.strftime("%Y-%m-%d")
    }
    assert_response :success
  end
end
