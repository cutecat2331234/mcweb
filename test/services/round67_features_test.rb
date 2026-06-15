# frozen_string_literal: true

require "test_helper"

class Round67WishlistFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @in_stock = Commerce::Product.create!(
      name: "In Stock Item",
      slug: "r67-is-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 1000,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_r67is_#{SecureRandom.hex(4)}"
    )
    @on_sale = Commerce::Product.create!(
      name: "Sale Item",
      slug: "r67-sale-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 800,
      compare_at_price_cents: 1200,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 3,
      public_id: "pub_r67sa_#{SecureRandom.hex(4)}"
    )
    @coming = Commerce::Product.create!(
      name: "Coming Soon",
      slug: "r67-soon-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 500,
      currency: "CNY",
      minimum_quantity: 1,
      available_at: 2.days.from_now,
      public_id: "pub_r67cs_#{SecureRandom.hex(4)}"
    )
    Commerce::WishlistItem.create!(user: @user, product: @in_stock)
    Commerce::WishlistItem.create!(user: @user, product: @on_sale)
    Commerce::WishlistItem.create!(user: @user, product: @coming)
    sign_in_as(@user)
  end

  test "wishlist index filters in_stock products" do
    get store_wishlist_path, params: { in_stock: "1" }
    assert_response :success
    assert_includes response.body, "In Stock Item"
    assert_includes response.body, "Sale Item"
    refute_includes response.body, "Coming Soon"
    assert_includes response.body, '"in_stock":true'
    assert_includes response.body, "filteredCount"
  end

  test "wishlist index filters coming_soon products" do
    get store_wishlist_path, params: { coming_soon: "1" }
    assert_response :success
    assert_includes response.body, "Coming Soon"
    refute_includes response.body, "In Stock Item"
  end

  test "wishlist index sorts by price ascending" do
    get store_wishlist_path, params: { sort: "price_asc" }
    assert_response :success
    assert_includes response.body, '"sort":"price_asc"'
  end
end

class Round67PaginationPropsTest < ActiveSupport::TestCase
  test "pagination component uses pageParam not query-param" do
    content = File.read(Rails.root.join("app/javascript/pages/Commerce/Products/Show.vue"))
    refute_includes content, 'query-param="review_page"'
    assert_includes content, 'page-param="review_page"'

    search = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    refute_includes search, 'query-param="post_page"'
    assert_includes search, 'page-param="post_page"'

    categories = File.read(Rails.root.join("app/javascript/pages/Commerce/Categories/Show.vue"))
    refute_includes categories, ":meta=\"pagination\""
    assert_includes categories, ":pagination=\"pagination\""
  end
end

class Round67CompareDiffHighlightTest < ActiveSupport::TestCase
  test "compare show page includes diff highlight helpers" do
    content = File.read(Rails.root.join("app/javascript/pages/Commerce/Compare/Show.vue"))
    assert_includes content, "rowHasDiff"
    assert_includes content, "cellDiffClass"
    assert_includes content, "compareRows"
  end
end
