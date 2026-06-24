# frozen_string_literal: true

require "test_helper"

class AutoBadgeRulesTest < ActiveSupport::TestCase
  setup do
    @user = create_user
  end

  def badge(rule, threshold)
    Community::Badge.create!(name: "B#{SecureRandom.hex(3)}", slug: "b-#{SecureRandom.hex(4)}", grant_rule: rule, grant_threshold: threshold)
  end

  test "grants a member_days badge once the account is old enough" do
    b = badge("member_days", 30)
    @user.update_column(:created_at, 40.days.ago)
    Community::CheckAutoBadges.call(user: @user)
    assert Community::UserBadge.exists?(user: @user, badge: b)
  end

  test "does not grant a member_days badge before the threshold" do
    b = badge("member_days", 30)
    @user.update_column(:created_at, 10.days.ago)
    Community::CheckAutoBadges.call(user: @user)
    assert_not Community::UserBadge.exists?(user: @user, badge: b)
  end

  test "grants a trust_level badge when the level is reached" do
    b = badge("trust_level", 0)
    Community::CheckAutoBadges.call(user: @user)
    assert Community::UserBadge.exists?(user: @user, badge: b)
  end

  test "grants a solutions badge based on accepted answers" do
    b = badge("solutions", 1)
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    asker = create_user
    topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}", section: section, user: asker, title: "Q",
      status: "published", last_posted_at: Time.current, last_post_user: asker, replies_count: 0
    )
    answer = Community::Post.create!(topic: topic, user: @user, floor_number: 2, body: "the answer", status: "published")
    topic.update!(solved_post_id: answer.id)

    Community::CheckAutoBadges.call(user: @user)
    assert Community::UserBadge.exists?(user: @user, badge: b)
  end
end
