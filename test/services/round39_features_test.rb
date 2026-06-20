# frozen_string_literal: true

require "test_helper"

class Community::RevokePollVoteTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r39-poll") { |c| c.name = "R39 Poll" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r39-poll-sec") { |s| s.name = "Poll"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "Poll",
      body: "OP",
      poll_question: "Q?",
      poll_options: %w[A B],
      ip_address: "127.0.0.1"
    ).value
    @poll = @topic.poll
    Community::VotePoll.call(user: @user, poll: @poll, option_index: 0)
  end

  test "user can revoke poll vote" do
    result = Community::RevokePollVote.call(user: @user, poll: @poll)
    assert result.success?
    assert_equal 0, @poll.votes.where(user: @user).count
  end
end

class Community::CreateUserSilenceTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.users.mute")
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r39-silence") { |c| c.name = "R39 Silence" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r39-silence-sec") { |s| s.name = "Silence"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: section, title: "T", body: "OP", ip_address: "127.0.0.1").value
  end

  test "silenced user cannot post" do
    Community::CreateUserSilence.call(actor: @mod, user: @user, reason: "Spam", days: 7)
    result = Community::CreatePost.call(user: @user, topic: @topic, body: "reply here", ip_address: "127.0.0.1")
    assert result.failure?
    assert_includes result.error.to_s, "禁言"
  end
end

class Community::SectionReadOnlyTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r39-ro") { |c| c.name = "R39 RO" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r39-ro-sec") { |s| s.name = "RO"; s.position = 0 }
    @section.update!(read_only: true)
    @topic = Community::CreateTopic.call(user: @mod, section: @section, title: "T", body: "OP", ip_address: "127.0.0.1").value
  end

  test "read only section blocks replies" do
    result = Community::CreatePost.call(user: @user, topic: @topic, body: "reply text", ip_address: "127.0.0.1")
    assert result.failure?
    assert_includes result.error.to_s, "只读"
  end
end

class Community::CannedResponseTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    Community::CannedResponse.create!(title: "Welcome", body: "Hello!", author: @mod)
  end

  test "canned response exists" do
    assert_equal 1, Community::CannedResponse.count
  end
end

class Community::ClearReportableHideTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "r39-hide") { |c| c.name = "R39 Hide" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r39-hide-sec") { |s| s.name = "Hide"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: section, title: "Hide", body: "OP", ip_address: "127.0.0.1").value
    @post = @topic.posts.first
    @post.update!(status: :hidden)
  end

  test "unhides when no pending reports" do
    result = Community::ClearReportableHide.call(reportable: @post)
    assert result.success?
    assert_equal "published", @post.reload.status
  end
end

class Community::ToggleSectionSubscriptionLevelTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r39-sec-sub") { |c| c.name = "R39 SecSub" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r39-sec-sub-sec") { |s| s.name = "Sec"; s.position = 0 }
    Community::Subscription.where(user: @user, subscribable: @section).delete_all
  end

  test "cycles section subscription levels" do
    r1 = Community::ToggleSectionSubscription.call(user: @user, section: @section)
    assert_equal "watching", r1.value[:notification_level]
    r2 = Community::ToggleSectionSubscription.call(user: @user, section: @section)
    assert_equal "tracking", r2.value[:notification_level]
  end
end

class Commerce::RecordGiftCardTransactionTest < ActiveSupport::TestCase
  setup do
    @card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(8).upcase}",
      balance_cents: 1000,
      initial_balance_cents: 1000,
      currency: "CNY",
      active: true
    )
  end

  test "records gift card transaction" do
    result = Commerce::RecordGiftCardTransaction.call(
      gift_card: @card,
      amount_cents: -200,
      transaction_type: "debit"
    )
    assert result.success?
    assert_equal 1, @card.transactions.count
  end
end

class Commerce::CategoryDescriptionTest < ActiveSupport::TestCase
  test "category accepts description" do
    cat = Commerce::Category.create!(name: "Desc Cat", slug: "desc-#{SecureRandom.hex(4)}", description: "About us")
    assert_equal "About us", cat.description
  end
end
