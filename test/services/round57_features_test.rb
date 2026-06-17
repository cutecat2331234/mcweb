# frozen_string_literal: true

require "test_helper"

class Round57FeaturesTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "r57user#{SecureRandom.hex(4)}", email: "r57-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123", status: :active, email_verified: true)
    @mod = User.create!(username: "r57mod#{SecureRandom.hex(4)}", email: "r57mod-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123", status: :active, email_verified: true)
    grant_permission(@mod, "forum.topics.lock")
    grant_permission(@mod, "forum.users.warn")
    grant_permission(@mod, "store.orders.read")
    grant_permission(@mod, "admin.access")

    category = Community::Category.find_or_create_by!(slug: "r57-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R57 Cat" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r57-sec-#{SecureRandom.hex(4)}") { |s| s.name = "R57 Sec"; s.position = 0 }
    @topic = Community::Topic.create!(public_id: "topic_#{SecureRandom.hex(8)}", section: @section, user: @user, title: "R57 Topic", status: :published, last_posted_at: Time.current, last_post_user: @user)
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hello", status: :published)
  end

  test "parse category: and has:images" do
    cat = Community::ParseSearchQuery.call(query: "category:games bugs has:images")
    assert cat.success?
    assert_equal "games", cat.value[:category_slug]
    assert_equal "images", cat.value[:images_filter]
    assert_equal "bugs", cat.value[:query]
  end

  test "tag group one_per_topic validation" do
    tag_a = Community::Tag.create!(name: "Type A", slug: "r57-type-a-#{SecureRandom.hex(3)}")
    tag_b = Community::Tag.create!(name: "Type B", slug: "r57-type-b-#{SecureRandom.hex(3)}")
    group = Community::TagGroup.create!(name: "Types", slug: "r57-types-#{SecureRandom.hex(3)}", one_per_topic: true)
    Community::TagGroupMembership.create!(tag_group: group, tag: tag_a)
    Community::TagGroupMembership.create!(tag_group: group, tag: tag_b)

    result = Community::SyncTopicTags.call(topic: @topic, tag_names: [ tag_a.name, tag_b.name ], user: @mod)
    assert result.failure?
    assert_match(/只能选一个/, result.error)
  end

  test "section required tag group" do
    tag = Community::Tag.create!(name: "Group Tag", slug: "r57-gtag-#{SecureRandom.hex(3)}")
    group = Community::TagGroup.create!(name: "Required G", slug: "r57-req-g-#{SecureRandom.hex(3)}")
    Community::TagGroupMembership.create!(tag_group: group, tag: tag)
    @section.update!(required_tag_group_ids: [ group.id ])

    result = Community::ValidateSectionTagGroups.call(section: @section, tag_ids: [])
    assert result.failure?
    assert_match(/标签组/, result.error)
  end

  test "auto archive scheduled topic" do
    @topic.update!(auto_archive_at: 1.minute.ago)
    result = Community::ArchiveScheduledTopic.call(topic: @topic)
    assert result.success?
    @topic.reload
    assert @topic.archived_at.present?
    assert_nil @topic.auto_archive_at
  end

  test "warning restrictions block posting" do
    SiteSetting.set("forum.warning_block_post_threshold", "3")
    Community::UserWarning.create!(user: @user, issuer: @mod, reason: "Spam", points: 3)
    result = Community::CheckWarningRestrictions.call(user: @user, action: :post)
    assert result.failure?
  end

  test "section onebox" do
    result = Community::FetchSectionOnebox.call(url: "/forum/sections/#{@section.slug}")
    assert result.success?
    assert_equal @section.name, result.value[:name]
  end

  test "tag onebox resolves synonym" do
    canonical = Community::Tag.create!(name: "Canonical", slug: "r57-canonical-#{SecureRandom.hex(3)}")
    synonym = Community::Tag.create!(name: "Synonym", slug: "r57-synonym-#{SecureRandom.hex(3)}", canonical_tag: canonical)
    result = Community::FetchTagOnebox.call(url: "/forum/tags/#{synonym.slug}")
    assert result.success?
    assert_equal canonical.name, result.value[:name]
  end

  test "store credit checkout flow" do
    @user.update!(store_credit_cents: 500)
    product = Commerce::Product.create!(name: "Credit Item", slug: "r57-credit-#{SecureRandom.hex(4)}", product_type: "virtual", status: :active, price_cents: 800, currency: "CNY", minimum_quantity: 1)
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: product, quantity: 1)

    order_result = Commerce::CreateOrder.call(cart: cart, user: @user)
    assert order_result.success?
    order = order_result.value
    assert_equal 500, order.store_credit_amount_cents
    assert_equal 300, order.total_cents

    Commerce::ConfirmPayment.call(
      payment_record: Payments::Record.create!(order: order, provider: "fake", amount_cents: order.total_cents, currency: "CNY", status: :pending),
      provider_payment_id: "test"
    )
    assert_equal 0, @user.reload.store_credit_cents
  end

  test "customer visible order note" do
    order = Commerce::Order.create!(public_id: "ord_#{SecureRandom.hex(8)}", order_number: "MC#{SecureRandom.hex(4).upcase}", user: @user, status: "paid", currency: "CNY", subtotal_cents: 100, total_cents: 100)
    result = Commerce::CreateOrderStaffNote.call(actor: @mod, order: order, body: "Ship soon", visible_to_customer: true)
    assert result.success?
    assert order.staff_notes.where(visible_to_customer: true).exists?
  end

  test "product scheduled availability scope" do
    future = Commerce::Product.create!(name: "Future", slug: "r57-future-#{SecureRandom.hex(4)}", product_type: "virtual", status: :active, price_cents: 100, currency: "CNY", minimum_quantity: 1, available_at: 1.day.from_now)
    assert_not_includes Commerce::Product.available, future
  end

  test "scheduled product activation job" do
    draft = Commerce::Product.create!(name: "Scheduled", slug: "r57-sched-#{SecureRandom.hex(4)}", product_type: "virtual", status: :draft, price_cents: 100, currency: "CNY", minimum_quantity: 1, available_at: 1.minute.ago)
    Commerce::ActivateScheduledProductsJob.perform_now
    assert_equal "active", draft.reload.status
  end

  test "@here respects forum.here preference" do
    participant = User.create!(username: "r57part#{SecureRandom.hex(4)}", email: "r57p-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123", status: :active, email_verified: true)
    Community::Post.create!(topic: @topic, user: participant, floor_number: 2, body: "Hi", status: :published)
    NotificationPreference.set!(participant, channel: "in_app", notification_type: "forum.here", enabled: false)

    Community::ProcessMentions.call(body: "Ping @here", author: @user, post: @topic.posts.first, topic: @topic)
    assert_equal 0, Notification.where(user: participant, notification_type: "forum.here").count
  end

  test "adjust store credit" do
    result = Commerce::AdjustStoreCredit.call(actor: @mod, user: @user, amount_cents: 1000, note: "Bonus")
    assert result.success?
    assert_equal 1000, @user.reload.store_credit_cents
  end
end
