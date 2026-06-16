# frozen_string_literal: true

require "test_helper"

class Community::PublishDraftRequiredTagsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r35-draft") { |c| c.name = "R35 Draft" }
    @tag = Community::Tag.create!(name: "draft-req-#{SecureRandom.hex(3)}", slug: "draft-req-#{SecureRandom.hex(4)}")
    @section = Community::Section.find_or_create_by!(category: category, slug: "r35-draft-sec") do |s|
      s.name = "Draft Sec"
      s.position = 0
      s.required_tag_ids = [ @tag.id ]
    end
    @section.update!(required_tag_ids: [ @tag.id ])
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Draft topic",
      status: "draft",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Draft body here", status: "published")
  end

  test "publish draft fails without required tag" do
    result = Community::PublishTopicDraft.call(user: @user, topic: @topic)
    assert result.failure?
    assert_match(/标签/, result.error.to_s)
  end

  test "publish draft succeeds with required tag" do
    Community::SyncTopicTags.call(topic: @topic, tag_names: [ @tag.name ], user: @user)
    result = Community::PublishTopicDraft.call(user: @user, topic: @topic)
    assert result.success?
    assert_equal "published", @topic.reload.status
  end
end

class Community::AllowedTagsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r35-allow") { |c| c.name = "R35 Allow" }
    @allowed = Community::Tag.create!(name: "allowed-#{SecureRandom.hex(3)}", slug: "allowed-#{SecureRandom.hex(4)}")
    @blocked = Community::Tag.create!(name: "blocked-#{SecureRandom.hex(3)}", slug: "blocked-#{SecureRandom.hex(4)}")
    @section = Community::Section.find_or_create_by!(category: category, slug: "r35-allow-sec") do |s|
      s.name = "Allow Sec"
      s.position = 0
      s.allowed_tag_ids = [ @allowed.id ]
    end
    @section.update!(allowed_tag_ids: [ @allowed.id ])
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Allowed tag topic",
      body: "Body content",
      tag_names: [ @allowed.name ],
      ip_address: "127.0.0.1"
    ).value
  end

  test "sync rejects disallowed tag" do
    result = Community::SyncTopicTags.call(topic: @topic, tag_names: [ @blocked.name ], user: @user)
    assert result.failure?
    assert_match(/不允许/, result.error.to_s)
  end
end

class Community::PrefixRequiredTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r35-prefix") { |c| c.name = "R35 Prefix" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r35-prefix-sec") do |s|
      s.name = "Prefix Sec"
      s.position = 0
      s.prefixes = [ "公告" ]
      s.prefix_required = true
    end
    @section.update!(prefixes: [ "公告" ], prefix_required: true)
  end

  test "create topic fails without required prefix" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "No prefix #{SecureRandom.hex(4)}",
      body: "Body content here",
      ip_address: "127.0.0.1"
    )
    assert result.failure?
    assert_match(/前缀/, result.error.to_s)
  end

  test "create topic succeeds with required prefix" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "With prefix #{SecureRandom.hex(4)}",
      body: "Body content here",
      prefix: "公告",
      ip_address: "127.0.0.1"
    )
    assert result.success?
    assert_equal "公告", result.value.prefix
  end
end

class Community::UserOneboxTest < ActiveSupport::TestCase
  setup do
    @user = create_user(username: "onebox_user_r35")
  end

  test "fetch user onebox" do
    result = Community::FetchUserOnebox.call(url: "/app/forum/users/#{@user.username}")
    assert result.success?
    assert_equal @user.username, result.value[:username]
  end

  test "format post body embeds user onebox" do
    result = Community::FormatPostBody.call(body: "/app/forum/users/#{@user.username}")
    assert result.success?
    assert_includes result.value, "user-onebox"
    assert_includes result.value, @user.username
  end
end

class Community::UploadTrustLevelTest < ActiveSupport::TestCase
  test "new user cannot upload images" do
    user = create_user
    assert_not Community::TrustLevel.can_upload_images?(user)
  end

  test "user with published post can upload images" do
    user = create_user
    category = Community::Category.find_or_create_by!(slug: "r35-upload") { |c| c.name = "R35 Up" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r35-upload-sec") { |s| s.name = "Up"; s.position = 0 }
    Community::CreateTopic.call(user: user, section: section, title: "Unlock upload", body: "OP body", ip_address: "127.0.0.1")
    assert Community::TrustLevel.can_upload_images?(user)
  end
end

class Commerce::Round35MailerTest < ActionMailer::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.price_drop", enabled: true)
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.refund_requested", enabled: true)
    @product = Commerce::Product.create!(
      public_id: "prod_r35_#{SecureRandom.hex(4)}",
      name: "R35 Product",
      slug: "r35-prod-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 80,
      currency: "CNY",
      stock: 5
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    @order.update!(status: "paid")
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      amount_cents: 80,
      currency: "CNY",
      status: "succeeded"
    )
    @refund = Commerce::Refund.create!(
      order: @order,
      payment_record: @payment,
      status: "pending",
      amount_cents: 80,
      reason: "Test",
      requested_by: @user,
      requested_by_customer: true
    )
  end

  test "price drop email" do
    assert_emails 1 do
      Commerce::OrderMailer.price_drop(@user.id, @product.id, 100, 80).deliver_now
    end
  end

  test "refund requested email" do
    assert_emails 1 do
      Commerce::OrderMailer.refund_requested(@refund.id).deliver_now
    end
  end
end

class Community::BookmarkReminderEmailTest < ActionMailer::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r35-bm") { |c| c.name = "R35 BM" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r35-bm-sec") { |s| s.name = "BM"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Bookmark", body: "OP").value
    @bookmark = Community::Bookmark.create!(user: @user, topic: @topic, note: "Check later", remind_at: 1.hour.ago)
    NotificationPreference.set!(@user, channel: "email", notification_type: "forum.bookmark_reminder", enabled: true)
  end

  test "bookmark reminder email sends" do
    assert_emails 1 do
      Community::ForumMailer.bookmark_reminder(@user.id, @bookmark.id).deliver_now
    end
  end
end
