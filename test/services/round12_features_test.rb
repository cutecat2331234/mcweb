# frozen_string_literal: true

require "test_helper"

class Community::FilterCensoredWordsTest < ActiveSupport::TestCase
  setup do
    Community::CensoredWord.create!(word: "spamword", replacement: "[已过滤]")
  end

  test "replaces censored words" do
    result = Community::FilterCensoredWords.call(text: "This is spamword content")
    assert result.success?
    assert_includes result.value, "[已过滤]"
    assert_not_includes result.value, "spamword"
  end
end

class Community::MergeTopicsTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.move")
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "merge-cat") { |c| c.name = "Merge" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "merge-sec") do |s|
      s.name = "Merge Sec"
      s.position = 0
    end
    @source = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Source #{SecureRandom.hex(4)}",
      body: "Source body",
      ip_address: "127.0.0.1"
    ).value
    @target = Community::CreateTopic.call(
      user: create_user,
      section: @section,
      title: "Target #{SecureRandom.hex(4)}",
      body: "Target body",
      ip_address: "127.0.0.1"
    ).value
    @reply_user = create_user
    Community::CreatePost.call(
      user: @reply_user,
      topic: @source,
      body: "Reply to merge",
      ip_address: "127.0.0.1"
    )
  end

  test "merges source replies into target" do
    result = Community::MergeTopics.call(user: @mod, source: @source, target_public_id: @target.public_id)
    assert result.success?
    assert_equal "hidden", @source.reload.status
    assert_operator @target.posts.count, :>=, 2
  end
end

class Community::DiffLinesTest < ActiveSupport::TestCase
  test "marks added and removed lines" do
    result = Community::DiffLines.call(before_text: "line1\nline2", after_text: "line1\nline3")
    assert result.success?
    kinds = result.value.map { |l| l[:kind] }
    assert_includes kinds, "removed"
    assert_includes kinds, "added"
  end
end

class Administration::BanUserTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    @target = create_user
  end

  test "bans user" do
    result = Administration::BanUser.call(user: @target, actor: @admin, reason: "spam")
    assert result.success?
    assert @target.reload.banned?
  end

  test "unbans user" do
    @target.ban!(reason: "test")
    result = Administration::UnbanUser.call(user: @target, actor: @admin)
    assert result.success?
    assert_equal "active", @target.reload.status
  end
end

class Commerce::CheckoutNotesTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_notes_#{SecureRandom.hex(4)}",
      name: "Notes Product",
      slug: "notes-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 10
    )
    @cart = Commerce::Cart.create!(user: @user)
    @cart.add_item!(product: @product, quantity: 1)
  end

  test "create order with notes" do
    result = Commerce::CreateOrder.call(cart: @cart, user: @user, notes: "请尽快发货")
    assert result.success?
    assert_equal "请尽快发货", result.value.notes
  end
end

class Commerce::AbandonedCartReminderTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_abandon_#{SecureRandom.hex(4)}",
      name: "Abandon",
      slug: "abandon-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @cart = Commerce::Cart.create!(user: @user, updated_at: 2.days.ago)
    @cart.add_item!(product: @product, quantity: 1)
  end

  test "job marks cart as reminded" do
    assert_nil @cart.abandoned_reminder_sent_at
    Commerce::AbandonedCartReminderJob.perform_now
    assert @cart.reload.abandoned_reminder_sent_at.present?
  end
end

class Commerce::GuestCartCountTest < ActiveSupport::TestCase
  test "session cart quantity sum" do
    cart = Commerce::Cart.create!
    product = Commerce::Product.create!(
      public_id: "prod_guest_#{SecureRandom.hex(4)}",
      name: "Guest",
      slug: "guest-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    cart.add_item!(product: product, quantity: 2)
    assert_equal 2, cart.items.sum(:quantity)
  end
end
