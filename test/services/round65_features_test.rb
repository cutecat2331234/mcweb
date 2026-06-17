# frozen_string_literal: true

require "test_helper"

class Round65AddWishlistToCompareTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @session = {}
  end

  test "imports available wishlist products into compare session" do
    p1 = Commerce::Product.create!(
      name: "Compare A", slug: "r65-ca-#{SecureRandom.hex(4)}",
      product_type: "virtual", status: :active, price_cents: 100,
      currency: "CNY", minimum_quantity: 1, stock: 5,
      public_id: "pub_r65a_#{SecureRandom.hex(4)}"
    )
    p2 = Commerce::Product.create!(
      name: "Compare B", slug: "r65-cb-#{SecureRandom.hex(4)}",
      product_type: "virtual", status: :active, price_cents: 200,
      currency: "CNY", minimum_quantity: 1, stock: 5,
      public_id: "pub_r65b_#{SecureRandom.hex(4)}"
    )
    upcoming = Commerce::Product.create!(
      name: "Soon", slug: "r65-soon-#{SecureRandom.hex(4)}",
      product_type: "virtual", status: :active, price_cents: 100,
      currency: "CNY", minimum_quantity: 1, available_at: 2.days.from_now,
      public_id: "pub_r65s_#{SecureRandom.hex(4)}"
    )
    Commerce::WishlistItem.create!(user: @user, product: p1)
    Commerce::WishlistItem.create!(user: @user, product: p2)
    Commerce::WishlistItem.create!(user: @user, product: upcoming)

    result = Commerce::AddWishlistToCompare.call(user: @user, session: @session)
    assert result.success?
    assert_equal 2, result.value[:added]
    assert_equal 2, @session[:compare_product_ids].size
    assert result.value[:skipped].any? { |s| s.include?("未上架") }
  end
end

class Round65SaveDraftRequiredGroupsTest < ActiveSupport::TestCase
  test "save draft rejects missing required tag group" do
    user = create_user
    category = Community::Category.find_or_create_by!(slug: "r65-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R65" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r65-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    group = Community::TagGroup.create!(name: "R65Req", slug: "r65-req-#{SecureRandom.hex(3)}")
    tag = Community::Tag.create!(name: "R65Tag", slug: "r65-t-#{SecureRandom.hex(3)}")
    Community::TagGroupMembership.create!(tag_group: group, tag: tag)
    section.update!(required_tag_group_ids: [ group.id ])

    result = Community::SaveTopicDraft.call(
      user: user,
      section: section,
      title: "Draft without tags",
      body: "Body content here"
    )
    assert result.failure?
    assert_match(/标签组/, result.error)
  end
end

class Round65CompareWishlistImportTest < ActionDispatch::IntegrationTest
  test "compare page exposes wishlist import props" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Import Me",
      slug: "r65-im-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_r65i_#{SecureRandom.hex(4)}"
    )
    Commerce::WishlistItem.create!(user: user, product: product)

    sign_in_as(user)
    get store_compare_path
    assert_response :success
    assert_includes response.body, "wishlistImportUrl"
    assert_includes response.body, "wishlistImportableCount"
  end
end
