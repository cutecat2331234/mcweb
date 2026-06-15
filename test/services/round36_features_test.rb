# frozen_string_literal: true

require "test_helper"

class Community::EstimateReadingTimeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r36-read") { |c| c.name = "R36 Read" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r36-read-sec") { |s| s.name = "Read"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "Reading time topic",
      body: "A" * 800,
      ip_address: "127.0.0.1"
    ).value
    Community::Post.create!(topic: @topic, user: @user, floor_number: 2, body: "B" * 400, status: "published")
  end

  test "estimates reading time from published posts" do
    result = Community::EstimateReadingTime.call(topic: @topic)
    assert result.success?
    assert_operator result.value[:minutes], :>=, 2
    assert_operator result.value[:word_count], :>=, 1200
  end
end

class Community::UserWarningMailerTest < ActionMailer::TestCase
  setup do
    @moderator = create_user
    grant_permission(@moderator, "forum.users.warn")
    @target = create_user
    NotificationPreference.set!(@target, channel: "email", notification_type: "forum.user_warning", enabled: true)
  end

  test "user warning email sends" do
    warning = Community::CreateUserWarning.call(
      actor: @moderator,
      user: @target,
      reason: "Rule violation",
      points: 1
    ).value

    assert_emails 1 do
      Community::ForumMailer.user_warning(@target.id, warning.id).deliver_now
    end
  end
end

class Community::CreateUserWarningTest < ActiveSupport::TestCase
  setup do
    @moderator = create_user
    grant_permission(@moderator, "forum.users.warn")
    @target = create_user
    NotificationPreference.set!(@target, channel: "in_app", notification_type: "forum.user_warning", enabled: true)
  end

  test "moderator can warn user" do
    result = Community::CreateUserWarning.call(
      actor: @moderator,
      user: @target,
      reason: "Spam posting",
      points: 2
    )
    assert result.success?
    assert_equal 2, Community::UserWarning.total_points_for(@target)
  end

  test "cannot warn self" do
    result = Community::CreateUserWarning.call(
      actor: @moderator,
      user: @moderator,
      reason: "Self",
      points: 1
    )
    assert result.failure?
    assert_match(/自己/, result.error.to_s)
  end
end

class Commerce::GiftCardTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_r36_#{SecureRandom.hex(4)}",
      name: "R36 Product",
      slug: "r36-prod-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      stock: 5
    )
    @gift_card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(10).upcase}",
      balance_cents: 300,
      initial_balance_cents: 300,
      currency: "CNY",
      active: true,
      created_by: @user
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @cart = cart
  end

  test "preview gift card applies partial balance" do
    result = Commerce::PreviewGiftCard.call(subtotal_cents: 1000, code: @gift_card.code)
    assert result.success?
    assert_equal 300, result.value[:gift_card_amount_cents]
    assert_equal 700, result.value[:total_cents]
    assert_not result.value.key?(:balance_cents)
  end

  test "create order with gift card reduces total" do
    order = Commerce::CreateOrder.call(cart: @cart, user: @user, gift_card_code: @gift_card.code).value
    assert_equal 300, order.gift_card_amount_cents
    assert_equal 700, order.total_cents
    assert_equal @gift_card.id, order.store_gift_card_id
  end

  test "debit gift card on payment" do
    order = Commerce::CreateOrder.call(cart: @cart, user: @user, gift_card_code: @gift_card.code).value
    Commerce::DebitGiftCard.call(order: order)
    assert_equal 0, @gift_card.reload.balance_cents
    assert_not @gift_card.active?
  end

  test "rejects expired gift card" do
    @gift_card.update!(expires_at: 1.day.ago)
    result = Commerce::PreviewGiftCard.call(subtotal_cents: 1000, code: @gift_card.code)
    assert result.failure?
    assert_match(/过期/, result.error.to_s)
  end

  test "prevents applying same gift card to multiple pending orders" do
    first = Commerce::CreateOrder.call(cart: @cart, user: @user, gift_card_code: @gift_card.code)
    assert first.success?

    cart2 = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart2, product: @product, quantity: 1)
    second = Commerce::CreateOrder.call(cart: cart2, user: @user, gift_card_code: @gift_card.code)

    assert second.failure?
    assert_match(/余额不足/, second.error.to_s)
  end
end

class Commerce::NewProductQuestionEmailTest < ActionMailer::TestCase
  setup do
    @staff = create_user
    grant_permission(@staff, "store.questions.answer")
    NotificationPreference.set!(@staff, channel: "email", notification_type: "commerce.new_product_question", enabled: true)
    @asker = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_q_r36_#{SecureRandom.hex(4)}",
      name: "Question Product",
      slug: "q-prod-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @question = Commerce::ProductQuestion.create!(
      product: @product,
      user: @asker,
      body: "Is this compatible?"
    )
  end

  test "new product question email sends" do
    assert_emails 1 do
      Commerce::OrderMailer.new_product_question(@staff.id, @question.id).deliver_now
    end
  end
end

class Commerce::AbandonedCartHtmlMailerTest < ActionMailer::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_ab_r36_#{SecureRandom.hex(4)}",
      name: "Abandoned Product",
      slug: "ab-prod-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 200,
      currency: "CNY",
      stock: 5
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @cart = cart
  end

  test "abandoned cart html email renders" do
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.abandoned_cart", enabled: true)
    email = Commerce::CartMailer.abandoned_cart(@cart.id)
    assert_includes email.html_part.body.to_s, @product.name
    assert_emails 1 do
      email.deliver_now
    end
  end
end
