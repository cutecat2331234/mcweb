# frozen_string_literal: true

require "test_helper"

module Community
  class AwardPointsTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @author = create_user
      @reactor = create_user
    end

    test "creates account and transaction and sets balance to amount" do
      result = Community::AwardPoints.call(user: @user, amount: 5, reason: "post_created")
      assert result.success?, "expected success, got #{result.error}"

      account = Community::PointAccount.find_by(user: @user, currency: "points")
      assert_not_nil account
      assert_equal 5, account.balance
      assert_equal 5, result.value[:balance]

      tx = result.value[:transaction]
      assert_equal 5, tx.amount
      assert_equal "post_created", tx.reason
      assert_equal 5, tx.balance_after
      assert_equal @user.id, tx.user_id
      assert_equal account.id, tx.forum_point_account_id
    end

    test "skips when amount is zero (rule disabled)" do
      result = Community::AwardPoints.call(user: @user, amount: 0, reason: "post_created")
      assert result.success?
      assert_equal true, result.value[:skipped]
      assert_nil Community::PointAccount.find_by(user: @user, currency: "points")
    end

    test "skips when amount is nil" do
      result = Community::AwardPoints.call(user: @user, amount: nil, reason: "post_created")
      assert result.success?
      assert_equal true, result.value[:skipped]
    end

    test "source-based idempotency: awarding twice for same source awards once" do
      post = build_published_post(@author)

      r1 = Community::AwardPoints.call(user: @author, amount: 5, reason: "post_created", source: post)
      r2 = Community::AwardPoints.call(user: @author, amount: 5, reason: "post_created", source: post)

      assert r1.success?
      assert r2.success?
      assert_equal true, r2.value[:duplicate]

      account = Community::PointAccount.find_by(user: @author, currency: "points")
      assert_equal 5, account.balance, "balance must not change on duplicate"
      assert_equal 1, account.transactions.where(reason: "post_created", source: post).count
    end

    test "dedupe_token idempotency: two awards with same token award once" do
      token = "reaction:#{build_published_post(@author).id}:#{@reactor.id}"

      r1 = Community::AwardPoints.call(user: @author, amount: 2, reason: "reaction_received", dedupe_token: token)
      r2 = Community::AwardPoints.call(user: @author, amount: 2, reason: "reaction_received", dedupe_token: token)

      assert r1.success?
      assert_equal true, r2.value[:duplicate]

      account = Community::PointAccount.find_by(user: @author, currency: "points")
      assert_equal 2, account.balance
      assert_equal 1, account.transactions.where(dedupe_token: token).count
    end

    test "balance_after is correct and balance equals sum of this account's transactions" do
      Community::AwardPoints.call(user: @user, amount: 5, reason: "post_created", source: build_published_post(@user))
      Community::AwardPoints.call(user: @user, amount: 10, reason: "admin_adjust")
      Community::AwardPoints.call(user: @user, amount: 3, reason: "admin_adjust")

      account = Community::PointAccount.find_by(user: @user, currency: "points")
      txs = account.transactions.order(:created_at, :id)
      assert_equal 18, account.balance
      assert_equal account.balance, txs.sum(:amount)
      # Running balance_after matches cumulative sum.
      running = 0
      txs.each do |tx|
        running += tx.amount
        assert_equal running, tx.balance_after
      end
    end

    test "admin_adjust is never deduped: repeated adjustments accumulate" do
      r1 = Community::AwardPoints.call(user: @user, amount: 10, reason: "admin_adjust")
      r2 = Community::AwardPoints.call(user: @user, amount: 10, reason: "admin_adjust")
      r3 = Community::AwardPoints.call(user: @user, amount: 5, reason: "admin_adjust")

      assert r1.success? && r2.success? && r3.success?
      refute r2.value[:duplicate], "admin_adjust must not be treated as duplicate"

      account = Community::PointAccount.find_by(user: @user, currency: "points")
      assert_equal 25, account.balance
      assert_equal 3, account.transactions.where(reason: "admin_adjust").count
    end

    test "negative admin_adjust below zero is rejected" do
      Community::AwardPoints.call(user: @user, amount: 10, reason: "admin_adjust")
      result = Community::AwardPoints.call(user: @user, amount: -50, reason: "admin_adjust")

      assert result.failure?
      assert_equal "point_balance_insufficient", result.error

      account = Community::PointAccount.find_by(user: @user, currency: "points")
      assert_equal 10, account.balance, "rejected deduction must not change balance"
    end

    test "negative admin_adjust within balance is allowed" do
      Community::AwardPoints.call(user: @user, amount: 30, reason: "admin_adjust")
      result = Community::AwardPoints.call(user: @user, amount: -20, reason: "admin_adjust")

      assert result.success?
      account = Community::PointAccount.find_by(user: @user, currency: "points")
      assert_equal 10, account.balance
    end

    # --- Integration via the real services ---

    test "creating a post awards the author the configured amount" do
      SiteSetting.set("forum.points.post_created", "7")
      section = build_section
      topic = build_topic(section, @author)

      result = Community::CreatePost.call(user: @author, topic: topic, body: "Hello world reply", skip_interval_check: true)
      assert result.success?, "post creation failed: #{result.error || result.errors}"

      post = result.value
      account = Community::PointAccount.find_by(user: @author, currency: "points")
      assert_not_nil account
      assert_equal 7, account.transactions.where(reason: "post_created", source: post).sum(:amount)
    end

    test "reacting to a post awards the post author, not the reactor" do
      SiteSetting.set("forum.points.reaction_received", "3")
      section = build_section
      topic = build_topic(section, @author)
      post = build_published_post(@author, topic: topic, floor: 1)

      result = Community::ToggleReaction.call(user: @reactor, post: post, emoji: "👍")
      assert result.success?, "reaction failed: #{result.error}"
      assert_equal true, result.value[:added]

      author_account = Community::PointAccount.find_by(user: @author, currency: "points")
      token = "reaction:#{post.id}:#{@reactor.id}"
      assert_equal 3, author_account.transactions.where(dedupe_token: token).sum(:amount)
      # Reactor is not rewarded for reacting.
      assert_nil Community::PointAccount.find_by(user: @reactor, currency: "points")
    end

    test "re-liking after unliking does not re-award (token dedupe survives toggle)" do
      SiteSetting.set("forum.points.reaction_received", "3")
      section = build_section
      topic = build_topic(section, @author)
      post = build_published_post(@author, topic: topic, floor: 1)

      Community::ToggleReaction.call(user: @reactor, post: post, emoji: "👍") # add
      Community::ToggleReaction.call(user: @reactor, post: post, emoji: "👍") # remove
      Community::ToggleReaction.call(user: @reactor, post: post, emoji: "👍") # add again

      author_account = Community::PointAccount.find_by(user: @author, currency: "points")
      token = "reaction:#{post.id}:#{@reactor.id}"
      assert_equal 1, author_account.transactions.where(dedupe_token: token).count
      assert_equal 3, author_account.balance
    end

    test "marking a topic solved awards the answer author keyed on the topic" do
      SiteSetting.set("forum.points.solution_accepted", "15")
      section = build_section
      topic = build_topic(section, @user)
      answer = build_published_post(@author, topic: topic, floor: 2)
      grant_permission(@user, "forum.topics.lock")

      result = Community::MarkTopicSolved.call(user: @user, topic: topic, post: answer)
      assert result.success?, "mark solved failed: #{result.error || result.errors}"

      author_account = Community::PointAccount.find_by(user: @author, currency: "points")
      assert_equal 15, author_account.transactions.where(reason: "solution_accepted", source: topic).sum(:amount)

      # Anti-farming: re-marking the SAME author's post as solution on the same
      # topic does not re-award (idempotent on beneficiary + reason + topic).
      another_answer_same_author = build_published_post(@author, topic: topic, floor: 3)
      Community::MarkTopicSolved.call(user: @user, topic: topic, post: another_answer_same_author)
      assert_equal 1, author_account.transactions.where(reason: "solution_accepted", source: topic).count
      assert_equal 15, author_account.reload.balance
    end

    private

    def build_section
      category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(4)}")
      Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(4)}", position: 0)
    end

    def build_topic(section, user)
      Community::Topic.create!(
        public_id: "t_#{SecureRandom.alphanumeric(12)}",
        section: section, user: user, title: "T", status: "published",
        last_posted_at: Time.current, last_post_user: user, replies_count: 0
      )
    end

    def build_published_post(user, topic: nil, floor: 1)
      topic ||= build_topic(build_section, user)
      Community::Post.create!(topic: topic, user: user, floor_number: floor, body: "body #{SecureRandom.hex(4)}", status: "published")
    end
  end
end
