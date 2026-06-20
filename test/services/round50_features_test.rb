# frozen_string_literal: true

require "test_helper"

class Community::TagSynonymTest < ActiveSupport::TestCase
  setup do
    @canonical = Community::Tag.create!(name: "Ruby", slug: "ruby")
    @synonym = Community::Tag.create!(name: "rb", slug: "rb", canonical_tag: @canonical)
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r50-tag") { |c| c.name = "T" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r50-tag-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Tag test", body: "OP", ip_address: "127.0.0.1").value
  end

  test "sync resolves synonym to canonical tag" do
    result = Community::SyncTopicTags.call(topic: @topic, tag_names: [ "rb" ], user: @user)
    assert result.success?
    assert_equal [ @canonical.id ], @topic.reload.tags.pluck(:id)
  end

  test "resolve_by_slug follows synonym" do
    assert_equal @canonical, Community::Tag.resolve_by_slug("rb")
  end
end

class Community::BumpScheduledTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r50-bump") { |c| c.name = "B" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r50-bump-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Bump", body: "OP", ip_address: "127.0.0.1").value
  end

  test "bumps topic when auto_bump_at passed" do
    @topic.update!(auto_bump_at: 1.minute.ago)
    result = Community::BumpScheduledTopic.call(topic: @topic)
    assert result.success?
    @topic.reload
    assert @topic.bumped_at.present?
    assert_nil @topic.auto_bump_at
  end
end

class Community::ExportPollResultsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r50-poll") { |c| c.name = "P" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r50-poll-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user, section: @section, title: "Poll", body: "OP",
      poll_question: "Q?", poll_options: %w[A B], ip_address: "127.0.0.1"
    ).value
    @poll = @topic.poll
    Community::VotePoll.call(user: @user, poll: @poll, option_index: 0)
  end

  test "exports csv with vote counts" do
    result = Community::ExportPollResults.call(poll: @poll)
    assert result.success?
    assert_includes result.value[:csv], "A"
    assert_includes result.value[:csv], @user.username
  end
end

class Commerce::GiftWrapTest < ActiveSupport::TestCase
  setup do
    enable_store_feature!(:physical_products)
    enable_store_feature!(:shipping)
    enable_store_feature!(:gift_wrap)
    @user = create_user
    SiteSetting.set("store.gift_wrap_cents", "300")
    @product = Commerce::Product.create!(
      name: "Physical", slug: "phys-#{SecureRandom.hex(4)}", public_id: "p_#{SecureRandom.hex(8)}",
      price_cents: 1000, currency: "CNY", product_type: "physical", requires_shipping: true, status: "active"
    )
    @cart = Commerce::Cart.create!(user: @user)
    @cart.add_item!(product: @product, quantity: 1)
  end

  test "create order with gift wrap adds fee" do
    result = Commerce::CreateOrder.call(
      cart: @cart,
      user: @user,
      gift_wrap: true,
      shipping_address: { "name" => "A", "phone" => "1", "line1" => "x", "city" => "y", "province" => "z" }
    )
    assert result.success?, result.error
    order = result.value
    assert order.gift_wrap?
    assert_equal 300, order.gift_wrap_cents
  end

  test "gift card covers gift wrap fee" do
    gift_card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(10).upcase}",
      balance_cents: 1300,
      initial_balance_cents: 1300,
      currency: "CNY",
      active: true,
      created_by: @user
    )
    order = Commerce::Order.create!(
      public_id: "ord_gw_#{SecureRandom.hex(6)}",
      order_number: "GW#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      shipping_cents: 0,
      gift_wrap_cents: 300,
      total_cents: 1300,
      currency: "CNY"
    )
    result = Commerce::ApplyGiftCard.call(order: order, code: gift_card.code)
    assert result.success?, result.error
    order.reload
    assert_equal 1300, order.gift_card_amount_cents
    assert_equal 0, order.total_cents
  end
end

class Commerce::OrderStaffNoteTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    grant_permission(@admin, "store.orders.read")
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000
    )
  end

  test "staff can add order note" do
    result = Commerce::CreateOrderStaffNote.call(actor: @admin, order: @order, body: "VIP customer")
    assert result.success?, result.error
    assert_equal 1, @order.staff_notes.count
  end
end

class Commerce::CompareShareTokenTest < ActiveSupport::TestCase
  test "ensures compare share token and stores product ids" do
    user = create_user
    result = Commerce::EnsureCompareShareToken.call(user: user, product_ids: %w[p1 p2])
    assert result.success?
    user.reload
    assert user.compare_share_token.present?
    assert_equal %w[p1 p2], user.compare_product_ids
  end
end
