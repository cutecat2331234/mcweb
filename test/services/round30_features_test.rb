# frozen_string_literal: true

require "test_helper"

class Commerce::PriceAlertsIndexTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Alert index product",
      slug: "alert-idx-r30-#{SecureRandom.hex(4)}",
      price_cents: 1200,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    Commerce::SubscribePriceAlert.call(user: @user, product: @product)
  end

  test "unsubscribe price alert" do
    result = Commerce::UnsubscribePriceAlert.call(user: @user, product: @product)
    assert result.success?
    assert_not Commerce::PriceAlert.exists?(user: @user, product: @product)
  end
end

class Community::IgnoresListTest < ActiveSupport::TestCase
  setup do
    @ignorer = create_user(username: "ignorer_r30")
    @ignored = create_user(username: "ignored_r30")
    Community::ToggleUserIgnore.call(ignorer: @ignorer, ignored_username: @ignored.username)
  end

  test "ignored user ids" do
    assert_includes Community::UserIgnore.ignored_user_ids(@ignorer), @ignored.id
  end
end

class Community::PrefixFilterTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r30-prefix") { |c| c.name = "R30 Prefix" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r30-prefix-sec") do |s|
      s.name = "Prefix Sec"
      s.position = 0
      s.prefixes = %w[Bug Feature]
    end
    @bug = Community::Topic.create!(
      section: @section,
      user: @user,
      title: "Bug topic",
      prefix: "Bug",
      status: :published,
      last_posted_at: Time.current,
      last_post_user: @user
    )
    @feature = Community::Topic.create!(
      section: @section,
      user: @user,
      title: "Feature topic",
      prefix: "Feature",
      status: :published,
      last_posted_at: Time.current,
      last_post_user: @user
    )
  end

  test "filters by prefix" do
    scope = @section.topics.where(status: :published)
    filtered = scope.where(prefix: "Bug")
    assert_includes filtered.map(&:id), @bug.id
    assert_not_includes filtered.map(&:id), @feature.id
  end
end

class Community::ProductOneboxTest < ActiveSupport::TestCase
  setup do
    @product = Commerce::Product.create!(
      public_id: "prod_onebox_r30",
      name: "Onebox Product",
      slug: "onebox-r30",
      summary: "Short desc",
      price_cents: 500,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
  end

  test "fetch product onebox by path" do
    result = Community::FetchProductOnebox.call(url: "/store/products/#{@product.public_id}")
    assert result.success?
    assert_equal @product.name, result.value[:name]
  end

  test "format post body embeds product onebox" do
    result = Community::FormatPostBody.call(body: "/store/products/#{@product.public_id}")
    assert result.success?
    assert_includes result.value, "product-onebox"
    assert_includes result.value, @product.name
  end
end

class Community::VerifiedPurchaserTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Verify product",
      slug: "verify-r30-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 100,
      total_cents: 100
    )
    Commerce::OrderItem.create!(
      order: order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 100,
      quantity: 1,
      total_cents: 100,
      fulfillment_snapshot: {}
    )
  end

  test "first purchase badge eligibility" do
    badge = Community::Badge.find_or_create_by!(slug: "first-purchase-r30") do |b|
      b.name = "认证买家"
      b.grant_rule = "first_purchase"
      b.icon = "🛒"
      b.color = "#16a34a"
    end
    assert Community::CheckAutoBadges.new(user: @user).send(:eligible?, badge)
  end
end

class Community::SectionMuteListTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r30-mute-list") { |c| c.name = "R30 Mute List" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r30-mute-list-sec") do |s|
      s.name = "Mute List"
      s.position = 0
    end
  end

  test "section mute record exists after toggle" do
    Community::ToggleSectionMute.call(user: @user, section: @section)
    assert Community::SectionMute.exists?(user: @user, section: @section)
  end
end
