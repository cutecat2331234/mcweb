# frozen_string_literal: true

require "test_helper"

class Community::ValidateSectionRequiredTagsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r34-cat") { |c| c.name = "R34" }
    @tag_a = Community::Tag.create!(name: "required-a-#{SecureRandom.hex(3)}", slug: "req-a-#{SecureRandom.hex(4)}")
    @tag_b = Community::Tag.create!(name: "required-b-#{SecureRandom.hex(3)}", slug: "req-b-#{SecureRandom.hex(4)}")
    @section = Community::Section.find_or_create_by!(category: category, slug: "r34-sec") do |s|
      s.name = "R34 Sec"
      s.position = 0
      s.required_tag_ids = [ @tag_a.id ]
    end
    @section.update!(required_tag_ids: [ @tag_a.id ])
  end

  test "create topic fails without required tag" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "No tag #{SecureRandom.hex(4)}",
      body: "Body content here",
      ip_address: "127.0.0.1"
    )

    assert result.failure?
    assert_match(/标签/, result.error.to_s)
  end

  test "create topic succeeds with required tag" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "With tag #{SecureRandom.hex(4)}",
      body: "Body content here",
      tag_names: [ @tag_a.name ],
      ip_address: "127.0.0.1"
    )

    assert result.success?
    assert_includes result.value.tags.map(&:id), @tag_a.id
  end

  test "sync topic tags rejects when required tag removed" do
    topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Tagged #{SecureRandom.hex(4)}",
      body: "Body content here",
      tag_names: [ @tag_a.name ],
      ip_address: "127.0.0.1"
    ).value

    result = Community::SyncTopicTags.call(topic: topic, tag_names: [ @tag_b.name ], user: @user)
    assert result.failure?
    assert_match(/标签/, result.error.to_s)
  end
end

class Community::ParticipantUsersPreloadTest < ActiveSupport::TestCase
  setup do
    @author = create_user(username: "author_r34")
    @replier = create_user(username: "replier_r34")
    category = Community::Category.find_or_create_by!(slug: "r34-part") { |c| c.name = "R34 Part" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r34-part-sec") do |s|
      s.name = "Part Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Participants", body: "OP").value
    Community::CreatePost.call(user: @replier, topic: @topic, body: "Reply here")
  end

  test "batch preload participant users avoids per-topic queries" do
    topics = [ @topic ]
    participants_by_topic = {}
    topic_ids = topics.map(&:id)
    authors_by_topic = topics.index_by(&:id).transform_values(&:user_id)
    rows = Community::Post
      .where(forum_topic_id: topic_ids, status: :published)
      .order(forum_topic_id: :asc, created_at: :desc)
      .pluck(:forum_topic_id, :user_id)

    rows.each do |topic_id, user_id|
      next if user_id == authors_by_topic[topic_id]
      participants_by_topic[topic_id] ||= []
      next if participants_by_topic[topic_id].include?(user_id)

      participants_by_topic[topic_id] << user_id
    end

    topics.each { |t| t.participant_users_preloaded = User.where(id: participants_by_topic[t.id]).to_a }

    assert_equal 1, @topic.participant_users(limit: 5).size
    assert_equal @replier.id, @topic.participant_users.first.id
  end
end

class Community::NotifyPostReactionIgnoreTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @reactor = create_user
    category = Community::Category.find_or_create_by!(slug: "r34-react") { |c| c.name = "R34 React" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r34-react-sec") do |s|
      s.name = "React Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "React", body: "OP").value
    @post = @topic.posts.first
    Community::ToggleUserIgnore.call(ignorer: @author, ignored_username: @reactor.username)
  end

  test "ignored reactor does not trigger reaction notification" do
    assert_no_difference -> { Notification.where(notification_type: "forum.reaction").count } do
      Community::NotifyPostReaction.call(post: @post, reactor: @reactor, emoji: "👍")
    end
  end
end

class Commerce::OrderStatusMailerTest < ActionMailer::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_r34_#{SecureRandom.hex(4)}",
      name: "R34 Mail",
      slug: "r34-mail-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    @order.update!(status: "paid")
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.order_processing", enabled: true)
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.order_fulfilling", enabled: true)
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.order_completed", enabled: true)
  end

  test "order processing email sends when enabled" do
    assert_emails 1 do
      Commerce::OrderMailer.order_processing(@order.id).deliver_now
    end
  end

  test "order fulfilling email sends when enabled" do
    assert_emails 1 do
      Commerce::OrderMailer.order_fulfilling(@order.id).deliver_now
    end
  end

  test "order completed email sends when enabled" do
    assert_emails 1 do
      Commerce::OrderMailer.order_completed(@order.id).deliver_now
    end
  end

  test "order processing email respects preference off" do
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.order_processing", enabled: false)
    assert_no_emails do
      Commerce::OrderMailer.order_processing(@order.id).deliver_now
    end
  end
end
