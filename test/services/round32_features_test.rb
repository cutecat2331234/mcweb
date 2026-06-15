# frozen_string_literal: true

require "test_helper"

class Community::TopicOneboxTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r32-onebox") { |c| c.name = "R32 Onebox" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r32-onebox-sec") do |s|
      s.name = "Onebox Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Onebox Topic", body: "OP").value
  end

  test "fetch topic onebox by path" do
    result = Community::FetchTopicOnebox.call(url: "/forum/topics/#{@topic.public_id}")
    assert result.success?
    assert_equal @topic.title, result.value[:title]
    assert_equal @user.username, result.value[:author]
  end

  test "format post body embeds topic onebox" do
    result = Community::FormatPostBody.call(body: "/forum/topics/#{@topic.public_id}")
    assert result.success?
    assert_includes result.value, "topic-onebox"
    assert_includes result.value, @topic.title
  end

  test "unlisted topic does not render onebox" do
    @topic.update!(unlisted: true)

    result = Community::FetchTopicOnebox.call(url: "/forum/topics/#{@topic.public_id}")
    assert result.success?
    assert_nil result.value

    formatted = Community::FormatPostBody.call(body: "/forum/topics/#{@topic.public_id}")
    assert formatted.success?
    assert_not_includes formatted.value, "topic-onebox"
  end
end

class Community::FilterNotificationRecipientsTest < ActiveSupport::TestCase
  setup do
    @actor = create_user(username: "actor_r32")
    @recipient = create_user(username: "recipient_r32")
    @ignorer = create_user(username: "ignorer_r32")
    Community::ToggleUserIgnore.call(ignorer: @ignorer, ignored_username: @actor.username)
  end

  test "filters ignored actor from recipients" do
    result = Community::FilterNotificationRecipients.call(
      actor_id: @actor.id,
      recipient_ids: [ @recipient.id, @ignorer.id ]
    )
    assert result.success?
    assert_includes result.value, @recipient.id
    assert_not_includes result.value, @ignorer.id
  end

  test "filters recipients who cannot view hidden topic" do
    author = create_user(username: "hidden_author_r32")
    subscriber = create_user(username: "hidden_sub_r32")
    category = Community::Category.find_or_create_by!(slug: "r32-hidden-notify") { |c| c.name = "R32 Hidden Notify" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r32-hidden-notify-sec") do |s|
      s.name = "Hidden Notify Sec"
      s.position = 0
    end
    topic = Community::CreateTopic.call(user: author, section: section, title: "Hidden notify", body: "OP").value
    topic.update!(status: "hidden")
    Community::Subscription.create!(user: subscriber, subscribable: topic)

    result = Community::FilterNotificationRecipients.call(
      actor_id: author.id,
      recipient_ids: [ subscriber.id, author.id ],
      topic: topic
    )

    assert result.success?
    assert_includes result.value, author.id
    assert_not_includes result.value, subscriber.id
  end
end

class Commerce::SubscribeProductDiscussionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r32-sub") { |c| c.name = "R32 Sub" }
    Community::Section.find_or_create_by!(category: category, slug: "r32-sub-sec") do |s|
      s.name = "Sub Sec"
      s.position = 0
    end
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Subscribe Product",
      slug: "sub-r32-#{SecureRandom.hex(4)}",
      price_cents: 500,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
  end

  test "subscribes buyer to product discussion" do
    result = Commerce::SubscribeProductDiscussion.call(user: @user, product: @product)
    assert result.success?
    assert Community::Subscription.exists?(user: @user, subscribable: result.value[:topic])
  end
end

class Commerce::ToggleAnswerHelpfulTest < ActiveSupport::TestCase
  setup do
    @asker = create_user(username: "asker_r32")
    @helper = create_user(username: "helper_r32")
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Answer Product",
      slug: "answer-r32-#{SecureRandom.hex(4)}",
      price_cents: 200,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @question = Commerce::CreateProductQuestion.call(user: @asker, product: @product, body: "How?").value
    @answer = Commerce::AnswerProductQuestion.call(user: @helper, question: @question, body: "Like this").value
  end

  test "toggle answer helpful" do
    result = Commerce::ToggleAnswerHelpful.call(user: @asker, answer: @answer)
    assert result.success?
    assert result.value[:helpful]
    assert_equal 1, result.value[:count]
  end

  test "cannot mark own answer helpful" do
    result = Commerce::ToggleAnswerHelpful.call(user: @helper, answer: @answer)
    assert result.failure?
  end
end

class Commerce::OrderLinkedQuestionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Order Q Product",
      slug: "orderq-r32-#{SecureRandom.hex(4)}",
      price_cents: 300,
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
      subtotal_cents: 300,
      total_cents: 300
    )
    @order_item = Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 300,
      quantity: 1,
      total_cents: 300,
      fulfillment_snapshot: {}
    )
  end

  test "create question with order item stores link" do
    result = Commerce::CreateProductQuestion.call(
      user: @user,
      product: @product,
      body: "Where is download?",
      order_item: @order_item
    )
    assert result.success?
    assert_equal @order_item.id, result.value.store_order_item_id
  end
end

class Community::NotifyIgnoreFilterTest < ActiveSupport::TestCase
  setup do
    @author = create_user(username: "author_r32n")
    @ignorer = create_user(username: "ignorer_r32n")
    category = Community::Category.find_or_create_by!(slug: "r32-notify") { |c| c.name = "R32 Notify" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r32-notify-sec") do |s|
      s.name = "Notify Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @author, section: section, title: "Notify", body: "OP").value
    Community::Subscription.create!(user: @ignorer, subscribable: @topic)
    Community::ToggleUserIgnore.call(ignorer: @ignorer, ignored_username: @author.username)
    NotificationPreference.set!(@ignorer, channel: "in_app", notification_type: "forum.topic_reply", enabled: true)
    @reply = Community::CreatePost.call(user: @author, topic: @topic, body: "Another post here", skip_interval_check: true).value
  end

  test "ignored author does not trigger reply notification" do
    assert_no_difference -> { Notification.where(user: @ignorer, notification_type: "forum.topic_reply").count } do
      Community::NotifyTopicReply.call(post: @reply)
    end
  end

  test "hidden topic reply does not notify subscribers who cannot view topic" do
    subscriber = create_user(username: "hidden_sub_notify")
    Community::Subscription.create!(user: subscriber, subscribable: @topic)
    NotificationPreference.set!(subscriber, channel: "in_app", notification_type: "forum.topic_reply", enabled: true)
    @topic.update!(status: "hidden")

    assert_no_difference -> { Notification.where(user: subscriber, notification_type: "forum.topic_reply").count } do
      Community::NotifyTopicReply.call(post: @reply)
    end
  end
end
