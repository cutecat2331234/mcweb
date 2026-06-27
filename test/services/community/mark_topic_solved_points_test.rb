# frozen_string_literal: true

require "test_helper"

module Community
  # Regression coverage for the self-award guard in
  # Community::MarkTopicSolved#award_solution_points. A topic owner is allowed to
  # mark their own topic solved (see SectionModeration#can_mark_solved?), so
  # without a guard a user could farm "solution_accepted" points by answering
  # their own topic and accepting their own answer. The guard mirrors the
  # self-reaction guard in Community::ToggleReaction.
  class MarkTopicSolvedPointsTest < ActiveSupport::TestCase
    setup do
      # Fresh users per test; balance/transaction assertions are scoped to a
      # specific user so residual rows from parallel workers can't make us flaky.
      @owner = create_user
      @answerer = create_user
      SiteSetting.set("forum.points.solution_accepted", "15")
    end

    test "marking your OWN post as the solution awards no solution_accepted points" do
      # Owner authors the topic AND the accepted answer, then marks it solved.
      topic = build_topic(build_section, @owner)
      own_answer = build_published_post(@owner, topic: topic, floor: 2)

      result = Community::MarkTopicSolved.call(user: @owner, topic: topic, post: own_answer)
      assert result.success?, "mark solved failed: #{result.error || result.errors}"
      assert_equal own_answer.id, topic.reload.solved_post_id, "topic should still be marked solved"

      # No points awarded to the self-marking author.
      account = Community::PointAccount.find_by(user: @owner, currency: "points")
      self_awarded = account ? account.transactions.where(reason: "solution_accepted", source: topic).sum(:amount) : 0
      assert_equal 0, self_awarded, "self-marked solution must not award points"
      assert_equal 0, points_balance(@owner), "balance must be unchanged for self-award"
    end

    test "accepting someone else's answer awards the answer author the points" do
      # Owner accepts a DIFFERENT user's answer -> author is rewarded.
      topic = build_topic(build_section, @owner)
      answer = build_published_post(@answerer, topic: topic, floor: 2)

      result = Community::MarkTopicSolved.call(user: @owner, topic: topic, post: answer)
      assert result.success?, "mark solved failed: #{result.error || result.errors}"

      author_account = Community::PointAccount.find_by(user: @answerer, currency: "points")
      assert_not_nil author_account, "answer author should have a points account"
      assert_equal 15, author_account.transactions.where(reason: "solution_accepted", source: topic).sum(:amount)
      assert_equal 15, points_balance(@answerer)

      # The marker (owner) earns nothing for accepting another user's answer.
      assert_equal 0, points_balance(@owner)
    end

    private

    def points_balance(user)
      Community::PointAccount.find_by(user: user, currency: "points")&.balance.to_i
    end

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
