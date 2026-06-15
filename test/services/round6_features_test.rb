# frozen_string_literal: true

require "test_helper"

class Community::ToggleUserBlockTest < ActiveSupport::TestCase
  setup do
    @blocker = create_user(username: "blocker1")
    @target = create_user(username: "target1")
  end

  test "user can block and unblock another user" do
    result = Community::ToggleUserBlock.call(blocker: @blocker, blocked_username: @target.username)
    assert result.success?
    assert result.value[:blocked]
    assert Community::UserBlock.exists?(blocker: @blocker, blocked: @target)

    unblock = Community::ToggleUserBlock.call(blocker: @blocker, blocked_username: @target.username)
    assert unblock.success?
    assert_not unblock.value[:blocked]
    assert_not Community::UserBlock.exists?(blocker: @blocker, blocked: @target)
  end

  test "cannot block yourself" do
    result = Community::ToggleUserBlock.call(blocker: @blocker, blocked_username: @blocker.username)
    assert result.failure?
  end
end

class Community::SaveTopicDraftTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "draft-cat") { |c| c.name = "Draft" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "draft-sec") do |s|
      s.name = "Draft Sec"
      s.position = 0
    end
  end

  test "saves and publishes draft" do
    save = Community::SaveTopicDraft.call(
      user: @user,
      section: @section,
      title: "Draft title",
      body: "Draft body content",
      tag_names: "test"
    )
    assert save.success?
    draft = save.value
    assert draft.draft?

    publish = Community::PublishTopicDraft.call(user: @user, topic: draft)
    assert publish.success?
    assert draft.reload.published?
  end
end

class Community::VotePollTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "poll-cat") { |c| c.name = "Poll" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "poll-sec") do |s|
      s.name = "Poll Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Poll topic",
      body: "Body",
      poll_question: "Favorite color?",
      poll_options: %w[Red Blue Green],
      ip_address: "127.0.0.1"
    ).value
    @poll = @topic.poll
  end

  test "user can vote on poll" do
    result = Community::VotePoll.call(user: @user, poll: @poll, option_index: 1)
    assert result.success?
    assert_equal 1, @poll.votes.find_by(user: @user).option_index
  end

  test "user cannot vote on poll in hidden topic" do
    @topic.update!(status: "hidden")
    other = create_user

    result = Community::VotePoll.call(user: other, poll: @poll, option_index: 0)

    assert result.failure?
    assert_match(/not allowed/i, result.error)
  end
end

class Community::CreateTopicPollTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "tpoll-cat") { |c| c.name = "TPoll" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "tpoll-sec") do |s|
      s.name = "TPoll Sec"
      s.position = 0
    end
  end

  test "creates topic with poll" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "With poll",
      body: "Content here",
      poll_question: "Yes or no?",
      poll_options: %w[Yes No],
      ip_address: "127.0.0.1"
    )
    assert result.success?
    assert result.value.poll.present?
    assert_equal 2, result.value.poll.options.size
  end
end

class Commerce::RequestRefundTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Refund Product",
      slug: "refund-product-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 10
    )
    @order_result = Commerce::CreateOrder.call(
      cart: build_cart(@user, @product),
      user: @user
    )
    assert @order_result.success?, @order_result.error
    @order = @order_result.value
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      provider_payment_id: "pay_#{SecureRandom.hex(8)}",
      amount_cents: @order.total_cents,
      currency: @order.currency,
      status: "succeeded"
    )
    @order.update!(status: "paid")
  end

  test "customer can request refund" do
    result = Commerce::RequestRefund.call(order: @order, user: @user, reason: "Changed mind")
    assert result.success?
    refund = result.value
    assert refund.pending?
    assert refund.requested_by_customer?
    assert_equal @order.total_cents, refund.amount_cents
  end

  test "cannot request refund twice" do
    Commerce::RequestRefund.call(order: @order, user: @user)
    result = Commerce::RequestRefund.call(order: @order, user: @user)
    assert result.failure?
  end

  private

  def build_cart(user, product)
    cart = Commerce::Cart.create!(user: user)
    cart.items.create!(product: product, quantity: 1)
    cart.reload
  end
end

class Community::UserBlockFilterTest < ActiveSupport::TestCase
  setup do
    @viewer = create_user(username: "viewer1")
    @blocked = create_user(username: "blocked1")
    Community::UserBlock.create!(blocker: @viewer, blocked: @blocked)
    category = Community::Category.find_or_create_by!(slug: "blk-cat") { |c| c.name = "Blk" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "blk-sec") do |s|
      s.name = "Blk Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @blocked,
      section: @section,
      title: "Blocked user topic",
      body: "Hidden from blocker",
      ip_address: "127.0.0.1"
    ).value
  end

  test "blocked_user_ids includes blocked users" do
    ids = Community::UserBlock.blocked_user_ids(@viewer)
    assert_includes ids, @blocked.id
  end
end
