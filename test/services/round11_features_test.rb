# frozen_string_literal: true

require "test_helper"

class Community::TopicPrefixTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "prefix-cat") { |c| c.name = "Prefix" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "prefix-sec") do |s|
      s.name = "Prefix Sec"
      s.position = 0
      s.prefixes = %w[公告 求助]
    end
  end

  test "create topic with valid prefix" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Help me",
      body: "Need help",
      prefix: "求助",
      ip_address: "127.0.0.1"
    )
    assert result.success?
    assert_equal "求助", result.value.prefix
  end

  test "invalid prefix is ignored" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Spam",
      body: "Body",
      prefix: "广告",
      ip_address: "127.0.0.1"
    )
    assert result.success?
    assert_nil result.value.prefix
  end
end

class Community::DraftVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    @other = create_user
    category = Community::Category.find_or_create_by!(slug: "vis-cat") { |c| c.name = "Vis" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "vis-sec") do |s|
      s.name = "Vis Sec"
      s.position = 0
    end
    @draft = Community::SaveTopicDraft.call(
      user: @author,
      section: @section,
      title: "Secret draft",
      body: "Hidden content"
    ).value
  end

  test "author can view draft topic" do
    sign_in_as(@author)
    get forum_topic_path(@draft)
    assert_response :success
  end

  test "other user cannot view draft topic" do
    sign_in_as(@other)
    get forum_topic_path(@draft)
    assert_response :not_found
  end
end

class Community::SyncTopicLastPostTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "sync-cat") { |c| c.name = "Sync" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "sync-sec") do |s|
      s.name = "Sync Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Sync topic",
      body: "First post",
      ip_address: "127.0.0.1"
    ).value
    @reply = Community::CreatePost.call(
      user: create_user,
      topic: @topic,
      body: "Second post",
      ip_address: "127.0.0.1"
    ).value
  end

  test "sync updates last post after reply deleted" do
    assert_equal 1, @topic.reload.replies_count
    @reply.soft_delete!
    Community::SyncTopicLastPost.call(topic: @topic)
    @topic.reload
    first_post = @topic.posts.order(:floor_number).first
    assert_equal 0, @topic.replies_count
    assert_equal first_post.created_at.to_i, @topic.last_posted_at.to_i
    assert_equal @user.id, @topic.last_post_user_id
  end
end

class Commerce::CartAccumulationTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_cart_acc_#{SecureRandom.hex(4)}",
      name: "Cart Acc",
      slug: "cart-acc-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 3
    )
    @cart = Commerce::Cart.create!(user: @user)
    @cart.add_item!(product: @product, quantity: 2)
  end

  test "adding more items validates accumulated quantity" do
    result = Commerce::ValidateCartItem.call(
      user: @user,
      product: @product,
      quantity: 2,
      cart: @cart
    )
    assert result.failure?
    assert_includes result.error, "库存"
  end
end

class Commerce::MergeGuestCartValidationTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_merge_#{SecureRandom.hex(4)}",
      name: "Merge",
      slug: "merge-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 2
    )
    @guest_cart = Commerce::Cart.create!
    @guest_cart.add_item!(product: @product, quantity: 2)
    @user_cart = Commerce::Cart.create!(user: @user)
    @user_cart.add_item!(product: @product, quantity: 1)
  end

  test "merge fails when combined quantity exceeds stock" do
    result = Commerce::MergeGuestCart.call(user: @user, session_token: @guest_cart.session_token)
    assert result.failure?
    assert @guest_cart.reload.items.exists?
  end
end

class Commerce::CancelPendingPaymentsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_cancel_pay_#{SecureRandom.hex(4)}",
      name: "Cancel Pay",
      slug: "cancel-pay-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 10
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      amount_cents: @order.total_cents,
      currency: "CNY",
      status: "pending"
    )
  end

  test "cancel order marks pending payments failed" do
    result = Commerce::CancelOrder.call(order: @order, actor: @user)
    assert result.success?
    assert_equal "failed", @payment.reload.status
  end
end

class Commerce::OrderMailerPreferenceTest < ActionMailer::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_mail_pref_#{SecureRandom.hex(4)}",
      name: "Mail Pref",
      slug: "mail-pref-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    NotificationPreference.set!(
      @user,
      channel: "email",
      notification_type: "commerce.order_created",
      enabled: false
    )
  end

  test "order created email respects preference" do
    assert_no_emails do
      Commerce::OrderMailer.order_created(@order.id).deliver_now
    end
  end
end

class Commerce::SalesMetricsVariantStockTest < ActiveSupport::TestCase
  test "low stock includes variants" do
    product = Commerce::Product.create!(
      public_id: "prod_low_var_#{SecureRandom.hex(4)}",
      name: "Low Var",
      slug: "low-var-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 100
    )
    product.variants.create!(name: "Small", sku: "S-1", price_cents: 100, stock: 2)

    result = Commerce::SalesMetrics.call
    assert result.success?
    assert_operator result.value[:low_stock_count], :>=, 1
  end
end

class Community::ReadStateUnreadTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "unread-cat") { |c| c.name = "Unread" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "unread-sec") do |s|
      s.name = "Unread Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Unread topic",
      body: "Body",
      ip_address: "127.0.0.1"
    ).value
    Community::ReadState.mark_read!(@user, @topic, floor: @topic.posts.maximum(:floor_number))
  end

  test "with_unread_for excludes fully read topics" do
    states = Community::ReadState.with_unread_for(@user)
    assert_not_includes states.map(&:forum_topic_id), @topic.id
  end
end
