# frozen_string_literal: true

require "test_helper"

class Community::ParseSearchQueryTest < ActiveSupport::TestCase
  test "parses in:section and @author from query" do
    result = Community::ParseSearchQuery.call(query: "hello in:general @alice")
    assert result.success?
    assert_equal "hello", result.value[:query]
    assert_equal "general", result.value[:section_slug]
    assert_equal "alice", result.value[:author]
  end

  test "parses author:username" do
    result = Community::ParseSearchQuery.call(query: "bug author:bob")
    assert result.success?
    assert_equal "bug", result.value[:query]
    assert_equal "bob", result.value[:author]
  end
end

class Community::CreateSmallActionPostTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r40-sa") { |c| c.name = "R40 SA" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r40-sa-sec") { |s| s.name = "SA"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: section, title: "T", body: "OP", ip_address: "127.0.0.1").value
  end

  test "creates small action post" do
    result = Community::CreateSmallActionPost.call(topic: @topic, actor: @mod, body: "主题已锁定。")
    assert result.success?
    assert_equal "small_action", result.value.post_type
  end
end

class Community::InviteTopicWatcherTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @invitee = create_user
    category = Community::Category.find_or_create_by!(slug: "r40-inv") { |c| c.name = "R40 Inv" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r40-inv-sec") { |s| s.name = "Inv"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: section, title: "Invite", body: "OP", ip_address: "127.0.0.1").value
  end

  test "author can invite watcher" do
    result = Community::InviteTopicWatcher.call(inviter: @author, topic: @topic, username: @invitee.username)
    assert result.success?
    assert Community::Subscription.exists?(user: @invitee, subscribable: @topic)
  end

  test "cannot invite twice" do
    Community::InviteTopicWatcher.call(inviter: @author, topic: @topic, username: @invitee.username)
    result = Community::InviteTopicWatcher.call(inviter: @author, topic: @topic, username: @invitee.username)
    assert result.failure?
  end
end

class Community::ReactionTrustLevelTest < ActiveSupport::TestCase
  setup do
    @previous_reaction_level = SiteSetting.get("forum.min_trust_level_reaction")
    SiteSetting.set("forum.min_trust_level_reaction", "2")
    @author = create_user
    @newbie = create_user
    category = Community::Category.find_or_create_by!(slug: "r40-react") { |c| c.name = "R40 React" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r40-react-sec") { |s| s.name = "React"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: section, title: "R", body: "OP", ip_address: "127.0.0.1").value
    @post = @topic.posts.first
  end

  teardown do
    if @previous_reaction_level.present?
      SiteSetting.set("forum.min_trust_level_reaction", @previous_reaction_level)
    else
      SiteSetting.where(key: "forum.min_trust_level_reaction").delete_all
    end
  end

  test "low trust user cannot react" do
    result = Community::ToggleReaction.call(user: @newbie, post: @post, emoji: "👍")
    assert result.failure?
    assert_includes result.error.to_s, "信任等级"
  end
end

class Community::SectionColorIconTest < ActiveSupport::TestCase
  test "section accepts color and icon" do
    category = Community::Category.find_or_create_by!(slug: "r40-color") { |c| c.name = "Color" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r40-color-sec") { |s| s.name = "Color"; s.position = 0 }
    section.update!(color_hex: "#ff0000", icon: "🔥")
    assert_equal "#ff0000", section.color_hex
    assert_equal "🔥", section.icon
  end
end

class Community::PostWikiTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @editor = create_user
    category = Community::Category.find_or_create_by!(slug: "r40-pwiki") { |c| c.name = "PW" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r40-pwiki-sec") { |s| s.name = "PW"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: section, title: "W", body: "OP", ip_address: "127.0.0.1").value
    @post = @topic.posts.first
    @post.update!(wiki: true)
  end

  test "wiki post editable by others" do
    assert Community::EditPost.editable_by?(@editor, @post)
  end
end

class Community::ModerateTopicSmallActionTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r40-mod") { |c| c.name = "Mod" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r40-mod-sec") { |s| s.name = "Mod"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: section, title: "M", body: "OP", ip_address: "127.0.0.1").value
  end

  test "lock creates small action post" do
    Community::ModerateTopic.call(user: @mod, topic: @topic, action: "lock")
    assert @topic.posts.where(post_type: "small_action").exists?
  end
end

class Commerce::FulfillGiftCardItemTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Gift Card 100",
      slug: "gc-100-#{SecureRandom.hex(4)}",
      product_type: "gift_card",
      price_cents: 10_000,
      currency: "CNY",
      status: "active",
      fulfillment_config: { "expiry_days" => 30 }
    )
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      user: @user,
      order_number: "ORD#{SecureRandom.hex(6).upcase}",
      status: "paid",
      subtotal_cents: 10_000,
      total_cents: 10_000,
      currency: "CNY"
    )
    @item = Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      quantity: 1,
      unit_price_cents: 10_000,
      total_cents: 10_000,
      fulfillment_snapshot: {
        "product_type" => "gift_card",
        "fulfillment_config" => { "expiry_days" => 30 }
      }
    )
  end

  test "issues gift card on fulfillment" do
    result = Commerce::FulfillGiftCardItem.call(order_item: @item)
    assert result.success?
    assert_equal 1, Commerce::GiftCard.where(source_order_item_id: @item.id).count
    card = Commerce::GiftCard.find_by(source_order_item_id: @item.id)
    assert_equal 10_000, card.balance_cents
    assert_equal @user.id, card.owner_user_id
  end
end
