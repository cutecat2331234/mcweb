# frozen_string_literal: true

require "test_helper"

class Community::CheckReportThresholdTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("forum.report_auto_hide_threshold", "2")
    @reporter1 = create_user
    @reporter2 = create_user
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "r38-report") { |c| c.name = "R38 Report" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r38-report-sec") { |s| s.name = "Report"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: section, title: "Report test", body: "OP", ip_address: "127.0.0.1").value
    @post = @topic.posts.first
  end

  test "auto hides post when report threshold reached" do
    Community::Report.create!(reporter: @reporter1, reportable: @post, reason: "spam", reason_code: "spam", status: :pending)
    report = Community::Report.create!(reporter: @reporter2, reportable: @post, reason: "spam", reason_code: "spam", status: :pending)
    result = Community::CheckReportThreshold.call(report: report)
    assert result.success?
    assert_equal "hidden", @post.reload.status
  end
end

class Community::ToggleSubscriptionLevelTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r38-sub") { |c| c.name = "R38 Sub" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r38-sub-sec") { |s| s.name = "Sub"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Sub test", body: "OP", ip_address: "127.0.0.1").value
    Community::Subscription.where(user: @user, subscribable: @topic).delete_all
  end

  test "cycles watching tracking and unsubscribe" do
    r1 = Community::ToggleSubscription.call(user: @user, topic: @topic)
    assert r1.value[:notification_level] == "watching"

    r2 = Community::ToggleSubscription.call(user: @user, topic: @topic)
    assert r2.value[:notification_level] == "tracking"

    r3 = Community::ToggleSubscription.call(user: @user, topic: @topic)
    assert_not r3.value[:watching]
  end
end

class Community::BanTopicReplyTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r38-ban") { |c| c.name = "R38 Ban" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r38-ban-sec") { |s| s.name = "Ban"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: section, title: "Ban test", body: "OP", ip_address: "127.0.0.1").value
  end

  test "banned user cannot reply" do
    Community::BanTopicReply.call(actor: @mod, topic: @topic, user: @user, reason: "Spam")
    result = Community::CreatePost.call(user: @user, topic: @topic, body: "reply text", ip_address: "127.0.0.1")
    assert result.failure?
    assert_includes result.error.to_s, "banned"
  end
end

class Community::CreateTopicStaffNoteTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r38-note") { |c| c.name = "R38 Note" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r38-note-sec") { |s| s.name = "Note"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Note test", body: "OP", ip_address: "127.0.0.1").value
  end

  test "moderator can add topic staff note" do
    result = Community::CreateTopicStaffNote.call(actor: @mod, topic: @topic, body: "Watch closely")
    assert result.success?
    assert_equal 1, @topic.staff_notes.count
  end
end

class Community::SectionTrustLevelTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r38-trust") { |c| c.name = "R38 Trust" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r38-trust-sec") do |s|
      s.name = "Trust"
      s.position = 0
      s.min_trust_level_create = 2
      s.min_trust_level_reply = 1
    end
    @section.update!(min_trust_level_create: 2, min_trust_level_reply: 1)
    @topic = Community::CreateTopic.call(user: create_user, section: @section, title: "Trust topic", body: "OP", ip_address: "127.0.0.1").value
  end

  test "low trust user cannot create topic" do
    result = Community::CreateTopic.call(user: @user, section: @section, title: "Fail", body: "Body text", ip_address: "127.0.0.1")
    assert result.failure?
  end
end

class Community::ArchiveConversationTest < ActiveSupport::TestCase
  setup do
    @sender = create_user
    grant_permission(@sender, "forum.topics.lock")
    @recipient = create_user
    result = Community::CreateConversation.call(sender: @sender, recipient_username: @recipient.username, body: "Hi")
    assert result.success?, result.error.to_s
    @conversation = result.value[:conversation]
  end

  test "archive hides conversation from default list" do
    Community::ArchiveConversation.call(user: @sender, conversation: @conversation)
    assert_empty Community::Conversation.for_user(@sender).to_a
    assert_equal 1, Community::Conversation.for_user(@sender, include_archived: true).count
  end
end

class Community::AnonymousPollTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r38-poll") { |c| c.name = "R38 Poll" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r38-poll-sec") { |s| s.name = "Poll"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "Poll",
      body: "OP",
      poll_question: "Q?",
      poll_options: %w[A B],
      poll_anonymous: true,
      ip_address: "127.0.0.1"
    ).value
    @poll = @topic.poll
  end

  test "poll is anonymous" do
    assert @poll.anonymous?
  end
end

class Commerce::DuplicateProductTest < ActiveSupport::TestCase
  setup do
    @product = Commerce::Product.create!(
      name: "Dup Product",
      slug: "dup-#{SecureRandom.hex(4)}",
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      price_cents: 1000,
      currency: "CNY",
      product_type: "digital",
      status: "active"
    )
    @product.variants.create!(name: "Default", sku: "SKU-#{SecureRandom.hex(4)}", price_cents: 1000, compare_at_price_cents: 1500)
  end

  test "duplicates product as draft with variants" do
    result = Commerce::DuplicateProduct.call(product: @product)
    assert result.success?
    copy = result.value
    assert_equal "draft", copy.status
    assert_equal 1, copy.variants.count
    assert_equal 1500, copy.variants.first.compare_at_price_cents
  end
end

class Commerce::ClaimGiftCardTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(8).upcase}",
      balance_cents: 500,
      initial_balance_cents: 500,
      currency: "CNY",
      active: true
    )
  end

  test "user can claim gift card" do
    result = Commerce::ClaimGiftCard.call(user: @user, gift_card: @card)
    assert result.success?
    assert_equal @user.id, @card.reload.owner_user_id
  end

  test "cannot claim gift card owned by another user" do
    other = create_user(username: "gift_owner_other")
    @card.update!(owner_user: other)

    result = Commerce::ClaimGiftCard.call(user: @user, gift_card: @card)
    assert result.failure?
    assert_match(/其他账户/, result.error.to_s)
  end
end

class Commerce::GiftCardShowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @other = create_user(username: "gift_card_other")
    @card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(8).upcase}",
      balance_cents: 500,
      initial_balance_cents: 500,
      currency: "CNY",
      active: true,
      owner_user: @owner
    )
  end

  test "gift card show hides balance from non owners" do
    get store_gift_card_path(code: @card.code)

    assert_response :success
    assert_not_includes response.body, "¥5.00"
  end

  test "gift card show shows balance to owner" do
    sign_in_as(@owner)
    get store_gift_card_path(code: @card.code)

    assert_response :success
    assert_includes response.body, "¥5.00"
  end
end

class Community::ReportAccessControlTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    @other = create_user(username: "report_other")
    category = Community::Category.find_or_create_by!(slug: "report-access-cat") { |c| c.name = "Report Access" }
    section = Community::Section.find_or_create_by!(category: category, slug: "report-access-sec") do |s|
      s.name = "Report Access Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: section,
      title: "Hidden report topic",
      body: "Opening",
      ip_address: "127.0.0.1"
    ).value
    @topic.update!(status: "hidden")
    @post = @topic.posts.first
  end

  test "reporting hidden topic returns not found" do
    sign_in_as(@other)
    post forum_reports_path, params: {
      report: {
        reportable_type: "Community::Topic",
        reportable_id: @topic.id,
        reason_code: "spam"
      }
    }

    assert_redirected_to root_path
    assert_equal "Content not found.", flash[:alert]
    assert_not Community::Report.exists?(reportable: @topic, reporter: @other)
  end

  test "reporting hidden post returns not found" do
    sign_in_as(@other)
    post forum_reports_path, params: {
      report: {
        reportable_type: "Community::Post",
        reportable_id: @post.id,
        reason_code: "spam"
      }
    }

    assert_redirected_to root_path
    assert_equal "Content not found.", flash[:alert]
    assert_not Community::Report.exists?(reportable: @post, reporter: @other)
  end
end

class Commerce::ProductVariantCompareAtTest < ActiveSupport::TestCase
  test "variant on_sale when compare_at higher" do
    product = Commerce::Product.create!(
      name: "Var Sale",
      slug: "var-sale-#{SecureRandom.hex(4)}",
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      price_cents: 800,
      currency: "CNY",
      product_type: "digital",
      status: "active"
    )
    variant = product.variants.create!(name: "V1", sku: "VSKU-#{SecureRandom.hex(4)}", price_cents: 800, compare_at_price_cents: 1200)
    assert variant.on_sale?
    assert_equal 33, variant.discount_percent
  end
end
