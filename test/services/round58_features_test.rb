# frozen_string_literal: true

require "test_helper"

class Round58FeaturesTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @mod = create_user
    grant_permission(@mod, "store.orders.read")
    grant_permission(@mod, "admin.access")

    category = Community::Category.find_or_create_by!(slug: "r58-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R58" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r58-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
  end

  test "category onebox" do
    result = Community::FetchCategoryOnebox.call(url: "/forum/categories/#{category_slug}")
    assert result.success?
    assert_equal category_slug, result.value[:slug]
  end

  test "upcoming products scope" do
    product = Commerce::Product.create!(
      name: "Soon", slug: "r58-soon-#{SecureRandom.hex(4)}",
      product_type: "virtual", status: :active, price_cents: 100,
      currency: "CNY", minimum_quantity: 1, available_at: 2.days.from_now
    )
    assert_includes Commerce::Product.upcoming, product
    assert_not_includes Commerce::Product.available, product
  end

  test "create order respects use_store_credit false" do
    @user.update!(store_credit_cents: 1000)
    product = Commerce::Product.create!(name: "Item", slug: "r58-item-#{SecureRandom.hex(4)}", product_type: "virtual", status: :active, price_cents: 500, currency: "CNY", minimum_quantity: 1)
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: product, quantity: 1)

    result = Commerce::CreateOrder.call(cart: cart, user: @user, use_store_credit: false)
    assert result.success?
    assert_equal 0, result.value.store_credit_amount_cents
    assert_equal 500, result.value.total_cents
  end

  test "wallet shows balance after adjustment" do
    Commerce::AdjustStoreCredit.call(actor: @mod, user: @user, amount_cents: 300, note: "Test")
    assert_equal 300, @user.reload.store_credit_cents
    assert_equal 1, @user.store_credit_transactions.count
  end

class Round58SearchSuggestTest < ActionDispatch::IntegrationTest
  test "search suggest resolves tag synonyms" do
    user = create_user
    canonical = Community::Tag.create!(name: "Canon", slug: "r58-canon-#{SecureRandom.hex(3)}")
    synonym = Community::Tag.create!(name: "SynonymX", slug: "r58-syn-#{SecureRandom.hex(3)}", canonical_tag: canonical)

    sign_in_as(user)
    get forum_search_suggest_path, params: { q: "Syn" }, as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert data["tags"].any? { |t| t["name"] == canonical.name }
  end
end

  def category_slug
    @section.category.slug
  end
end

class Round58CategoryOneboxFormatTest < ActiveSupport::TestCase
  test "format post body renders category onebox" do
    category = Community::Category.find_or_create_by!(slug: "r58-fmt-#{SecureRandom.hex(4)}") { |c| c.name = "Fmt" }
    result = Community::FormatPostBody.call(body: "/forum/categories/#{category.slug}")
    assert result.success?
    assert_includes result.value, "category-onebox"
    assert_includes result.value, category.name
  end
end
