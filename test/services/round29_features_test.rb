# frozen_string_literal: true

require "test_helper"

class Community::SectionMuteTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r29-sec-mute") { |c| c.name = "R29 Mute" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r29-sec-mute-sec") do |s|
      s.name = "Mute Sec"
      s.position = 0
    end
    Community::ToggleSectionSubscription.call(user: @user, section: @section)
  end

  test "section mute filters new topic notifications" do
    Community::ToggleSectionMute.call(user: @user, section: @section)
    author = create_user(username: "sec_author_r29")

    assert_no_difference -> { Notification.where(user: @user, notification_type: "forum.section_topic").count } do
      Community::NotifySectionTopic.call(
        topic: Community::CreateTopic.call(user: author, section: @section, title: "New", body: "Body").value
      )
    end
  end

  test "toggle section mute" do
    result = Community::ToggleSectionMute.call(user: @user, section: @section)
    assert result.success?
    assert result.value[:muted]
    assert Community::SectionMute.exists?(user: @user, section: @section)
  end
end

class Community::UserIgnoreTest < ActiveSupport::TestCase
  setup do
    @ignorer = create_user(username: "ignorer_r29")
    @ignored = create_user(username: "ignored_r29")
  end

  test "toggle user ignore" do
    result = Community::ToggleUserIgnore.call(ignorer: @ignorer, ignored_username: @ignored.username)
    assert result.success?
    assert result.value[:ignored]
    assert Community::UserIgnore.exists?(ignorer: @ignorer, ignored: @ignored)
  end

  test "cannot ignore self" do
    result = Community::ToggleUserIgnore.call(ignorer: @ignorer, ignored_username: @ignorer.username)
    assert result.failure?
  end
end

class Community::LockReasonTest < ActiveSupport::TestCase
  setup do
    @mod = create_user(username: "mod_r29")
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r29-lock") { |c| c.name = "R29 Lock" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r29-lock-sec") { |s| s.name = "Lock"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: @section, title: "Lock test", body: "OP").value
  end

  test "lock stores reason" do
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "lock", lock_reason: "违规内容")
    assert result.success?
    @topic.reload
    assert @topic.locked?
    assert_equal "违规内容", @topic.lock_reason
  end

  test "unlock clears reason" do
    Community::ModerateTopic.call(user: @mod, topic: @topic, action: "lock", lock_reason: "spam")
    Community::ModerateTopic.call(user: @mod, topic: @topic, action: "unlock")
    @topic.reload
    assert_not @topic.locked?
    assert_nil @topic.lock_reason
  end
end

class Community::SelfReactionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r29-react") { |c| c.name = "R29 React" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r29-react-sec") { |s| s.name = "React"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "React", body: "OP").value
    @post = @topic.posts.first
  end

  test "cannot react to own post" do
    result = Community::ToggleReaction.call(user: @user, post: @post, emoji: "👍")
    assert result.failure?
    assert_includes result.error, "不能给自己的帖子点反应"
  end
end

class Community::ParticipantUsersTest < ActiveSupport::TestCase
  setup do
    @author = create_user(username: "author_r29")
    @replier = create_user(username: "replier_r29")
    category = Community::Category.find_or_create_by!(slug: "r29-part") { |c| c.name = "R29 Part" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r29-part-sec") { |s| s.name = "Part"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Participants", body: "OP").value
    Community::Post.create!(topic: @topic, user: @replier, floor_number: 2, body: "Reply", status: "published")
  end

  test "participant users excludes author" do
    participants = @topic.participant_users(limit: 5)
    assert_includes participants.map(&:id), @replier.id
    assert_not_includes participants.map(&:id), @author.id
  end
end

class Commerce::ClearCartTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @cart = Commerce::Cart.create!(user: @user)
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Clear cart item",
      slug: "clear-r29-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @cart.add_item!(product: @product, quantity: 1)
  end

  test "clears all cart items" do
    result = Commerce::ClearCart.call(cart: @cart)
    assert result.success?
    assert_equal 0, @cart.items.count
  end
end

class Commerce::PriceAlertTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Alert product",
      slug: "alert-r29-#{SecureRandom.hex(4)}",
      price_cents: 1000,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
  end

  test "subscribe price alert" do
    result = Commerce::SubscribePriceAlert.call(user: @user, product: @product)
    assert result.success?
    alert = Commerce::PriceAlert.find_by(user: @user, product: @product)
    assert_equal 1000, alert.baseline_price_cents
  end

  test "notify price drop job sends notification" do
    Commerce::SubscribePriceAlert.call(user: @user, product: @product)
    @product.update!(price_cents: 800)

    assert_difference -> { Notification.where(user: @user, notification_type: "commerce.price_drop").count }, 1 do
      Commerce::NotifyPriceDropJob.perform_now(@product.id)
    end
  end
end

class Commerce::ProductSummaryTest < ActiveSupport::TestCase
  test "product summary column" do
    product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Summary product",
      slug: "summary-r29-#{SecureRandom.hex(4)}",
      summary: "简短介绍",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    assert_equal "简短介绍", product.summary
  end
end
