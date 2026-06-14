# frozen_string_literal: true

require "test_helper"
require "ostruct"

class Community::CreateGroupConversationTest < ActiveSupport::TestCase
  setup do
    @sender = create_user
    enable_forum_pm!(@sender)
    @alice = create_user(username: "alice_#{SecureRandom.hex(3)}")
    @bob = create_user(username: "bob_#{SecureRandom.hex(3)}")
  end

  test "creates group conversation with participants" do
    result = Community::CreateGroupConversation.call(
      sender: @sender,
      title: "项目讨论",
      recipient_usernames: [ @alice.username, @bob.username ],
      body: "大家好"
    )

    assert result.success?
    conversation = result.value[:conversation]
    assert conversation.is_group?
    assert_equal "项目讨论", conversation.title
    assert_equal 3, conversation.users.count
    assert_equal @sender.id, conversation.creator_id
  end

  test "rejects empty title" do
    result = Community::CreateGroupConversation.call(
      sender: @sender,
      title: "",
      recipient_usernames: [ @alice.username ],
      body: "hi"
    )

    assert result.failure?
  end
end

class Community::CreateConversationGroupIsolationTest < ActiveSupport::TestCase
  setup do
    @sender = create_user
    enable_forum_pm!(@sender)
    @recipient = create_user
  end

  test "does not reuse group conversation for direct message" do
    group = Community::CreateGroupConversation.call(
      sender: @sender,
      title: "群组",
      recipient_usernames: [ @recipient.username ],
      body: "group msg"
    ).value[:conversation]

    result = Community::CreateConversation.call(
      sender: @sender,
      recipient_username: @recipient.username,
      body: "direct msg"
    )

    assert result.success?
    assert_not_equal group.id, result.value[:conversation].id
    assert_not result.value[:conversation].is_group?
  end
end

class Community::SyncTopicTagsStaffOnlyTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @staff = create_user
    grant_permission(@staff, "forum.tags.manage")

    category = Community::Category.find_or_create_by!(slug: "tag-cat-#{SecureRandom.hex(3)}") { |c| c.name = "Tag Cat" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "tag-sec-#{SecureRandom.hex(3)}") do |s|
      s.name = "Tag Sec"
      s.position = 0
    end

    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Tagged #{SecureRandom.hex(4)}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )

    @staff_tag = Community::Tag.create!(name: "staff-only-#{SecureRandom.hex(3)}", slug: "staff-#{SecureRandom.hex(4)}", staff_only: true)
  end

  test "blocks regular user from staff-only tag" do
    result = Community::SyncTopicTags.call(topic: @topic, tag_names: [ @staff_tag.name ], user: @user)
    assert result.failure?
  end

  test "allows staff to use staff-only tag" do
    result = Community::SyncTopicTags.call(topic: @topic, tag_names: [ @staff_tag.name ], user: @staff)
    assert result.success?
    assert_includes @topic.reload.tags, @staff_tag
  end
end

class Commerce::HideProductQuestionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_h_#{SecureRandom.hex(4)}",
      name: "Hide Q Product",
      slug: "hide-q-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @question = Commerce::CreateProductQuestion.call(user: @user, product: @product, body: "问题").value
  end

  test "hides product question" do
    result = Commerce::HideProductQuestion.call(question: @question)
    assert result.success?
    assert @question.reload.hidden?
  end
end

class Commerce::AttachProductCoverTest < ActiveSupport::TestCase
  setup do
    @product = Commerce::Product.create!(
      public_id: "prod_cov_#{SecureRandom.hex(4)}",
      name: "Cover Product",
      slug: "cover-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake-image"),
      filename: "cover.png",
      content_type: "image/png"
    )
  end

  test "attaches cover image to product" do
    result = Commerce::AttachProductCover.call(product: @product, signed_id: @blob.signed_id)
    assert result.success?
    assert @product.reload.cover_image.attached?
  end
end

class Payments::StripeProviderWebhookTest < ActiveSupport::TestCase
  setup do
    @order = Commerce::Order.create!(
      user: create_user,
      order_number: "ORD-WH-#{SecureRandom.hex(4)}",
      status: "pending",
      subtotal_cents: 500,
      discount_cents: 0,
      total_cents: 500,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "stripe",
      amount_cents: 500,
      currency: "CNY",
      status: "pending",
      provider_payment_id: "stripe_wh_#{SecureRandom.hex(4)}"
    )
  end

  test "locates payment by checkout session metadata" do
    provider = Payments::StripeProvider.new
    event = OpenStruct.new(
      event_id: "evt_#{SecureRandom.hex(4)}",
      event_type: "checkout.session.completed",
      payload: {
        "data" => {
          "object" => {
            "id" => "cs_test_#{SecureRandom.hex(4)}",
            "metadata" => { "payment_record_id" => @payment.id.to_s }
          }
        }
      }
    )

    located = provider.send(:locate_payment_record, event)
    assert_equal @payment.id, located.id
  end

  test "rejects invalid stripe signature when secret configured" do
    config = Payments::ProviderConfig.find_or_create_by!(provider: "stripe") do |c|
      c.enabled = true
    end
    config.update!(credentials: { webhook_secret: "whsec_round15" })
    provider = Payments::StripeProvider.new
    refute provider.verify_webhook_signature(payload: "{}", signature: "", headers: { "HTTP_STRIPE_SIGNATURE" => "t=1,v1=abc" })
  end
end
