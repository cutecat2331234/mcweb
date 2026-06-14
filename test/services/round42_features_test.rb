# frozen_string_literal: true

require "test_helper"

class Community::ParseSearchQuerySolvedTest < ActiveSupport::TestCase
  test "parses is:solved from query" do
    result = Community::ParseSearchQuery.call(query: "rails is:solved")
    assert result.success?
    assert_equal "rails", result.value[:query]
    assert_equal "solved", result.value[:solved_filter]
  end

  test "parses is:unsolved from query" do
    result = Community::ParseSearchQuery.call(query: "help is:unsolved")
    assert result.success?
    assert_equal "help", result.value[:query]
    assert_equal "unsolved", result.value[:solved_filter]
  end
end

class Community::ForumCategoryStyleTest < ActiveSupport::TestCase
  test "category accepts color and icon" do
    cat = Community::Category.create!(
      name: "Styled Cat",
      slug: "styled-#{SecureRandom.hex(4)}",
      color_hex: "#ff0000",
      icon: "📁"
    )
    assert_equal "#ff0000", cat.color_hex
    assert_equal "📁", cat.icon
  end
end

class Community::SectionBannerTest < ActiveSupport::TestCase
  test "section accepts banner text" do
    category = Community::Category.find_or_create_by!(slug: "r42-banner") { |c| c.name = "Banner" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r42-banner-sec") do |s|
      s.name = "B"
      s.position = 0
      s.banner_text = "欢迎发帖"
    end
    assert_equal "欢迎发帖", section.banner_text
  end
end

class Community::AutoCloseOnSolvedTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r42-solve") { |c| c.name = "Solve" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r42-solve-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Q", body: "OP", ip_address: "127.0.0.1").value
    @reply = Community::CreatePost.call(user: @user, topic: @topic, body: "Answer", skip_interval_check: true).value
    @previous = SiteSetting.get("forum.auto_close_on_solved")
    SiteSetting.set("forum.auto_close_on_solved", "1")
  end

  teardown do
    if @previous
      SiteSetting.set("forum.auto_close_on_solved", @previous)
    else
      SiteSetting.where(key: "forum.auto_close_on_solved").delete_all
    end
  end

  test "marks solved and auto closes topic" do
    result = Community::MarkTopicSolved.call(user: @user, topic: @topic, post: @reply)
    assert result.success?
    @topic.reload
    assert @topic.locked?
    assert_equal @reply.id, @topic.solved_post_id
    assert @topic.posts.where(post_type: "small_action").exists?
  end
end

class Commerce::CalculateShippingTest < ActiveSupport::TestCase
  setup do
    @prev_min = SiteSetting.get("store.free_shipping_min_order_cents")
    @prev_flat = SiteSetting.get("store.flat_shipping_cents")
    SiteSetting.set("store.free_shipping_min_order_cents", "10000")
    SiteSetting.set("store.flat_shipping_cents", "800")
  end

  teardown do
    SiteSetting.set("store.free_shipping_min_order_cents", @prev_min) if @prev_min
    SiteSetting.set("store.flat_shipping_cents", @prev_flat) if @prev_flat
  end

  test "charges flat shipping below threshold" do
    result = Commerce::CalculateShipping.call(subtotal_cents: 5000)
    assert result.success?
    assert_equal 800, result.value[:shipping_cents]
    assert_not result.value[:free_shipping]
    assert_equal 5000, result.value[:amount_remaining_cents]
  end

  test "free shipping at or above threshold" do
    result = Commerce::CalculateShipping.call(subtotal_cents: 10_000)
    assert result.success?
    assert_equal 0, result.value[:shipping_cents]
    assert result.value[:free_shipping]
  end
end

class Commerce::OrderShippingTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Ship Product",
      slug: "ship-#{SecureRandom.hex(4)}",
      product_type: "digital",
      price_cents: 5000,
      currency: "CNY",
      status: "active"
    )
    @prev_flat = SiteSetting.get("store.flat_shipping_cents")
    SiteSetting.set("store.free_shipping_min_order_cents", "0")
    SiteSetting.set("store.flat_shipping_cents", "600")
    cart = Commerce::Cart.create!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user).value
  end

  teardown do
    SiteSetting.set("store.flat_shipping_cents", @prev_flat) if @prev_flat
  end

  test "order includes shipping in total" do
    assert_equal 600, @order.shipping_cents
    assert_equal 5600, @order.total_cents
  end
end

class Commerce::WishlistNoteTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Note Product",
      slug: "note-#{SecureRandom.hex(4)}",
      product_type: "digital",
      price_cents: 1000,
      currency: "CNY",
      status: "active"
    )
    Commerce::ToggleWishlist.call(user: @user, product: @product)
  end

  test "updates wishlist note" do
    result = Commerce::UpdateWishlistNote.call(user: @user, product: @product, note: "生日愿望")
    assert result.success?
    item = Commerce::WishlistItem.find_by!(user: @user, product: @product)
    assert_equal "生日愿望", item.note
  end

  test "clears wishlist note" do
    Commerce::UpdateWishlistNote.call(user: @user, product: @product, note: "tmp")
    result = Commerce::UpdateWishlistNote.call(user: @user, product: @product, note: "")
    assert result.success?
    assert_nil Commerce::WishlistItem.find_by!(user: @user, product: @product).note
  end
end
