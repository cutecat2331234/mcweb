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
    assert_match(/无权/, result.error)
  end
end

class Community::PollVotersAccessTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "poll-voters-cat") { |c| c.name = "Poll Voters" }
    section = Community::Section.find_or_create_by!(category: category, slug: "poll-voters-sec") do |s|
      s.name = "Poll Voters Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "Poll voters topic",
      body: "Body",
      poll_question: "Pick one?",
      poll_options: %w[A B],
      ip_address: "127.0.0.1"
    ).value
    @poll = @topic.poll
    Community::VotePoll.call(user: @user, poll: @poll, option_index: 0)
  end

  test "voters endpoint rejects hidden topics for regular users" do
    @topic.update!(status: "hidden")
    other = create_user
    sign_in_as(other)

    get voters_forum_poll_path(@poll), as: :json

    assert_response :forbidden
  end
end

class Community::ToggleReactionVisibilityTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @other = create_user
    category = Community::Category.find_or_create_by!(slug: "react-vis-cat") { |c| c.name = "React Vis" }
    section = Community::Section.find_or_create_by!(category: category, slug: "react-vis-sec") do |s|
      s.name = "React Vis Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: section,
      title: "Hidden react topic",
      body: "Body",
      ip_address: "127.0.0.1"
    ).value
    @post = @topic.posts.first
  end

  test "cannot react on hidden topic without moderation permission" do
    @topic.update!(status: "hidden")

    result = Community::ToggleReaction.call(user: @other, post: @post, emoji: "👍")

    assert result.failure?
    assert_match(/not available/i, result.error)
  end

  test "cannot react on hidden post without moderation permission" do
    @post.update!(status: :hidden)

    result = Community::ToggleReaction.call(user: @other, post: @post, emoji: "👍")

    assert result.failure?
    assert_match(/not available/i, result.error)
  end
end

class Community::PostRawAccessTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "raw-access-cat") { |c| c.name = "Raw Access" }
    section = Community::Section.find_or_create_by!(category: category, slug: "raw-access-sec") do |s|
      s.name = "Raw Access Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: section,
      title: "Raw access topic",
      body: "Opening post",
      ip_address: "127.0.0.1"
    ).value
    @post = @topic.posts.first
  end

  test "raw hides moderated posts from regular users" do
    @post.update!(status: :hidden)
    other = create_user
    sign_in_as(other)

    get raw_forum_post_path(@post)

    assert_response :not_found
  end
end

class Community::HiddenPostTopicListTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    @other = create_user
    category = Community::Category.find_or_create_by!(slug: "hidden-list-cat") { |c| c.name = "Hidden List" }
    section = Community::Section.find_or_create_by!(category: category, slug: "hidden-list-sec") do |s|
      s.name = "Hidden List Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: section,
      title: "Hidden list topic",
      body: "Opening post",
      ip_address: "127.0.0.1"
    ).value
    @reply = Community::CreatePost.call(
      user: @other,
      topic: @topic,
      body: "Visible reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    ).value
    @reply.update!(status: :hidden)
  end

  test "topic page omits hidden posts for regular users" do
    sign_in_as(@author)

    get forum_topic_path(@topic)

    assert_response :success
    assert_includes response.body, "Opening post"
    assert_not_includes response.body, "Visible reply"
  end

  test "create post rejects quoting hidden posts" do
    sign_in_as(@author)

    result = Community::CreatePost.call(
      user: @author,
      topic: @topic,
      body: "Quote attempt",
      quoted_post: @reply,
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )

    assert result.failure?
    assert_match(/quoted post is not available/i, result.error)
  end
end

class Community::HiddenTopicActivityFeedTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "activity-hidden-cat") { |c| c.name = "Activity Hidden" }
    section = Community::Section.find_or_create_by!(category: category, slug: "activity-hidden-sec") do |s|
      s.name = "Activity Hidden Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: section,
      title: "Hidden activity topic",
      body: "Opening",
      ip_address: "127.0.0.1"
    ).value
    @topic.update!(status: "hidden")
    @reply = Community::CreatePost.call(
      user: @author,
      topic: @topic,
      body: "Secret hidden reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    ).value
  end

  test "activity feed omits posts from hidden topics" do
    get forum_activity_path(tab: "posts")

    assert_response :success
    assert_not_includes response.body, "Secret hidden reply"
  end
end

class Community::HiddenTopicNotificationDisplayTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    @subscriber = create_user(username: "notif_subscriber")
    category = Community::Category.find_or_create_by!(slug: "notif-hidden-cat") { |c| c.name = "Notif Hidden" }
    section = Community::Section.find_or_create_by!(category: category, slug: "notif-hidden-sec") do |s|
      s.name = "Notif Hidden Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: section,
      title: "Secret hidden notification topic",
      body: "Opening",
      ip_address: "127.0.0.1"
    ).value
    Community::Subscription.subscribe!(@subscriber, @topic)
    @topic.update!(status: "hidden")
    Notification.notify!(
      user: @subscriber,
      notification_type: "forum.topic_reply",
      title: "主题有新回复：Secret hidden notification topic",
      body: "leaked reply excerpt",
      metadata: { topic_id: @topic.public_id, path: "/app/forum/topics/#{@topic.public_id}" }
    )
  end

  test "notification list redacts hidden topic content for subscriber" do
    sign_in_as(@subscriber)
    get forum_notifications_path

    assert_response :success
    assert_not_includes response.body, "Secret hidden notification topic"
    assert_not_includes response.body, "leaked reply excerpt"
    assert_includes response.body, "内容不可用"
  end
end

class Community::HiddenTopicEnumerationTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    @other = create_user(username: "hidden_enum_user")
    category = Community::Category.find_or_create_by!(slug: "enum-hidden-cat") { |c| c.name = "Enum Hidden" }
    section = Community::Section.find_or_create_by!(category: category, slug: "enum-hidden-sec") do |s|
      s.name = "Enum Hidden Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: section,
      title: "Hidden enum topic",
      body: "Opening",
      ip_address: "127.0.0.1"
    ).value
    @topic.update!(status: "hidden")
  end

  test "create post on hidden topic returns not found for other users" do
    sign_in_as(@other)
    post forum_posts_path, params: { post: { topic_id: @topic.public_id, body: "probe" } }

    assert_response :not_found
  end

  test "reply draft on hidden topic returns not found for other users" do
    sign_in_as(@other)
    patch forum_topic_reply_draft_path(@topic), params: { body: "probe" }

    assert_response :not_found
  end
end

class Community::PostAccessControlTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "post-access-cat") { |c| c.name = "Post Access" }
    section = Community::Section.find_or_create_by!(category: category, slug: "post-access-sec") do |s|
      s.name = "Post Access Sec"
      s.position = 0
    end
    @topic = Community::SaveTopicDraft.call(
      user: @author,
      section: section,
      title: "Draft post access",
      body: "Secret draft body"
    ).value
    @post = @topic.posts.first
  end

  test "raw post body is unavailable for draft topics to guests" do
    get raw_forum_post_path(@post)

    assert_response :not_found
  end

  test "edit post allows author on hidden topic" do
    publish = Community::PublishTopicDraft.call(user: @author, topic: @topic)
    assert publish.success?
    @topic.update!(status: "hidden")

    result = Community::EditPost.call(user: @author, post: @post, body: "Updated hidden topic body")

    assert result.success?
  end

  test "edit post rejects hidden topics for other users" do
    publish = Community::PublishTopicDraft.call(user: @author, topic: @topic)
    assert publish.success?
    @topic.update!(status: "hidden")
    other = create_user

    result = Community::EditPost.call(user: other, post: @post, body: "Attempted edit text")

    assert result.failure?
    assert_match(/not available/i, result.error)
  end

  test "fork topic rejects hidden source posts for other users" do
    publish = Community::PublishTopicDraft.call(user: @author, topic: @topic)
    assert publish.success?
    @topic.update!(status: "hidden")
    other = create_user

    result = Community::CreateTopicFromPost.call(user: other, post: @post, ip_address: "127.0.0.1")

    assert result.failure?
    assert_match(/not available/i, result.error)
  end

  test "create post rejects hidden topics for other users" do
    publish = Community::PublishTopicDraft.call(user: @author, topic: @topic)
    assert publish.success?
    @topic.update!(status: "hidden")
    other = create_user

    result = Community::CreatePost.call(user: other, topic: @topic, body: "Sneaky reply", ip_address: "127.0.0.1", skip_interval_check: true)

    assert result.failure?
    assert_match(/not available/i, result.error)
  end

  test "save reply draft rejects hidden topics for other users" do
    publish = Community::PublishTopicDraft.call(user: @author, topic: @topic)
    assert publish.success?
    @topic.update!(status: "hidden")
    other = create_user

    result = Community::SaveReplyDraft.call(user: other, topic: @topic, body: "Draft reply")

    assert result.failure?
    assert_match(/not available/i, result.error)
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
    enable_refund_window!
    anchor_order_payment_at!(@order)
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
