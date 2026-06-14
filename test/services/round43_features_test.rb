# frozen_string_literal: true

require "test_helper"

class Community::ParseSearchQueryTopicFlagsTest < ActiveSupport::TestCase
  test "parses is:locked and is:pinned" do
    result = Community::ParseSearchQuery.call(query: "help is:locked is:pinned")
    assert result.success?
    assert_equal "help", result.value[:query]
    assert_equal "locked", result.value[:locked_filter]
    assert_equal "pinned", result.value[:pinned_filter]
  end

  test "parses is:wiki" do
    result = Community::ParseSearchQuery.call(query: "docs is:wiki")
    assert result.success?
    assert_equal "wiki", result.value[:wiki_filter]
  end
end

class Community::ApplyTopicSearchFiltersTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @user2 = create_user
    category = Community::Category.find_or_create_by!(slug: "r43-filter") { |c| c.name = "F" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r43-filter-sec") { |s| s.name = "S"; s.position = 0 }
    @locked = Community::CreateTopic.call(user: @user, section: section, title: "Locked", body: "OP", ip_address: "127.0.0.1").value
    @locked.update!(locked: true)
    @wiki = Community::CreateTopic.call(user: @user2, section: section, title: "Wiki", body: "OP2", ip_address: "127.0.0.1").value
    @wiki.update!(wiki: true)
  end

  test "filters locked topics" do
    scope = Community::Topic.published_listed
    result = Community::ApplyTopicSearchFilters.call(scope: scope, locked_filter: "locked")
    assert_includes result.value.pluck(:id), @locked.id
    assert_not_includes result.value.pluck(:id), @wiki.id
  end

  test "filters wiki topics" do
    scope = Community::Topic.published_listed
    result = Community::ApplyTopicSearchFilters.call(scope: scope, wiki_filter: "wiki")
    assert_includes result.value.pluck(:id), @wiki.id
  end
end

class Community::ForumCategoryDescriptionTest < ActiveSupport::TestCase
  test "category stores description" do
    cat = Community::Category.create!(
      name: "Desc",
      slug: "desc-#{SecureRandom.hex(4)}",
      description: "General discussion"
    )
    assert_equal "General discussion", cat.description
  end
end

class Commerce::AllowBackorderTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Backorder Product",
      slug: "bo-#{SecureRandom.hex(4)}",
      product_type: "digital",
      price_cents: 1000,
      currency: "CNY",
      status: "active",
      stock: 0,
      allow_backorder: true
    )
  end

  test "backorder available when out of stock" do
    assert @product.backorder_available?
    assert @product.purchasable?
  end

  test "validate cart allows backorder" do
    cart = Commerce::Cart.create!(user: @user)
    result = Commerce::ValidateCartItem.call(user: @user, product: @product, quantity: 1, cart: cart)
    assert result.success?
  end

  test "create order with backorder keeps stock at zero" do
    cart = Commerce::Cart.create!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
    order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    assert order.persisted?
    assert_equal 0, @product.reload.stock
  end
end

class Commerce::CompareMaxItemsSettingTest < ActiveSupport::TestCase
  setup do
    @previous = SiteSetting.get("store.compare_max_items")
    SiteSetting.set("store.compare_max_items", "2")
    @session = {}
    @products = 3.times.map do |i|
      Commerce::Product.create!(
        name: "Compare #{i}",
        slug: "cmp-#{i}-#{SecureRandom.hex(3)}",
        product_type: "digital",
        price_cents: 100,
        currency: "CNY",
        status: "active"
      )
    end
  end

  teardown do
    if @previous
      SiteSetting.set("store.compare_max_items", @previous)
    else
      SiteSetting.where(key: "store.compare_max_items").delete_all
    end
  end

  test "respects compare max items setting" do
    Commerce::ToggleCompare.call(session: @session, product: @products[0])
    Commerce::ToggleCompare.call(session: @session, product: @products[1])
    result = Commerce::ToggleCompare.call(session: @session, product: @products[2])
    assert result.failure?
    assert_equal 2, Commerce::ToggleCompare.compare_max_items
  end
end
