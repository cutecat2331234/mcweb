# frozen_string_literal: true

require "test_helper"

class Community::UnreadControllerTest < ActionDispatch::IntegrationTest
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
    other = create_user
    Community::CreatePost.call(user: other, topic: @topic, body: "Reply post")
    sign_in_as(@user)
  end

  test "unread page loads without sql error" do
    get forum_unread_path
    assert_response :success
  end
end

class Community::NestedReplyTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "nest-cat") { |c| c.name = "Nest" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "nest-sec") do |s|
      s.name = "Nest Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Nested",
      body: "Opening",
      ip_address: "127.0.0.1"
    ).value
    @parent = @topic.posts.first
  end

  test "creates nested reply" do
    replier = create_user
    result = Community::CreatePost.call(
      user: replier,
      topic: @topic,
      body: "Child reply",
      parent_post: @parent
    )
    assert result.success?
    assert_equal @parent.id, result.value.parent_post_id
  end
end

class Community::SlowModeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "slow-cat") { |c| c.name = "Slow" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "slow-sec") do |s|
      s.name = "Slow Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Slow mode",
      body: "Body",
      ip_address: "127.0.0.1"
    ).value
    @topic.update!(slow_mode_seconds: 3600)
  end

  test "slow mode blocks rapid replies" do
    result = Community::CreatePost.call(user: @user, topic: @topic, body: "Too fast")
    assert result.failure?
    assert_match(/Slow mode/i, result.error)
  end
end

class Community::MarkTopicSolvedTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "solve-cat") { |c| c.name = "Solve" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "solve-sec") do |s|
      s.name = "Solve Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Question",
      body: "Help?",
      ip_address: "127.0.0.1"
    ).value
    @reply_user = create_user
    @reply = Community::CreatePost.call(user: @reply_user, topic: @topic, body: "Answer here").value
    assert @reply, "reply should be created"
  end

  test "topic author can mark solved" do
    result = Community::MarkTopicSolved.call(user: @user, topic: @topic, post: @reply)
    assert result.success?
    assert_equal @reply.id, @topic.reload.solved_post_id
  end
end

class Community::WikiEditTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @editor = create_user
    category = Community::Category.find_or_create_by!(slug: "wiki-cat") { |c| c.name = "Wiki" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "wiki-sec") do |s|
      s.name = "Wiki Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Wiki topic",
      body: "Original",
      ip_address: "127.0.0.1"
    ).value
    @topic.update!(wiki: true)
    @post = @topic.posts.first
  end

  test "wiki allows other users to edit" do
    assert Community::EditPost.editable_by?(@editor, @post)
  end
end

class Community::FormatPostBodyRichTest < ActiveSupport::TestCase
  test "renders fenced code and spoiler" do
    body = <<~MD
      ```ruby
      puts "hi"
      ```
      ||secret||
    MD
    result = Community::FormatPostBody.call(body: body)
    assert result.success?
    assert_includes result.value, "<pre"
    assert_includes result.value, "spoiler"
  end
end

class Commerce::ProcessRefundPendingTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user
    @product = Commerce::Product.create!(
      name: "Pending Refund Product",
      slug: "pending-refund-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 800,
      currency: "CNY",
      stock: 10
    )
    cart = Commerce::Cart.create!(user: @user)
    cart.items.create!(product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      provider_payment_id: "pay_#{SecureRandom.hex(8)}",
      amount_cents: @order.total_cents,
      currency: @order.currency,
      status: "succeeded"
    )
    @order.update!(status: "paid")
    @pending = Commerce::RequestRefund.call(order: @order, user: @user).value
  end

  test "approves existing pending refund instead of duplicating" do
    result = Commerce::ProcessRefund.call(
      order: @order,
      payment_record: @payment,
      amount_cents: @pending.amount_cents,
      approved_by: @admin,
      existing_refund: @pending
    )
    assert result.success?
    assert_equal 1, @order.refunds.count
    assert @pending.reload.completed?
  end
end

class Community::BlockedMessageTest < ActiveSupport::TestCase
  setup do
    @blocker = create_user
    @blocked = create_user
    Community::UserBlock.create!(blocker: @blocker, blocked: @blocked)
  end

  test "blocked users cannot start conversation" do
    result = Community::CreateConversation.call(
      sender: @blocker,
      recipient_username: @blocked.username,
      body: "Hello"
    )
    assert result.failure?
  end
end
