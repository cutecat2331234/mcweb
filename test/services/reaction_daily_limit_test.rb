# frozen_string_literal: true

require "test_helper"

class ReactionDailyLimitTest < ActiveSupport::TestCase
  setup do
    @reactor = create_user
    @author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    @posts = Array.new(3) do |i|
      topic = Community::Topic.create!(
        public_id: "t_#{SecureRandom.alphanumeric(10)}",
        section: @section, user: @author, title: "T#{i}", status: "published",
        last_posted_at: Time.current, last_post_user: @author, replies_count: 0
      )
      Community::Post.create!(topic: topic, user: @author, floor_number: 1, body: "post #{i}", status: "published")
    end
  end

  test "enforces the daily reaction cap (scaled by trust level)" do
    SiteSetting.set("forum.max_daily_reactions", "2") # trust level 0 => limit 2
    assert Community::ToggleReaction.call(user: @reactor, post: @posts[0], emoji: "👍").success?
    assert Community::ToggleReaction.call(user: @reactor, post: @posts[1], emoji: "👍").success?

    third = Community::ToggleReaction.call(user: @reactor, post: @posts[2], emoji: "👍")
    assert third.failure?
    assert_equal 2, Community::Reaction.where(user: @reactor).count
  end

  test "is unlimited when the setting is zero" do
    SiteSetting.set("forum.max_daily_reactions", "0")
    @posts.each { |p| assert Community::ToggleReaction.call(user: @reactor, post: p, emoji: "👍").success? }
  end

  test "removing a reaction is allowed even at the cap" do
    SiteSetting.set("forum.max_daily_reactions", "1")
    assert Community::ToggleReaction.call(user: @reactor, post: @posts[0], emoji: "👍").success?
    # toggling the same reaction off is not "adding", so the cap does not block it
    assert Community::ToggleReaction.call(user: @reactor, post: @posts[0], emoji: "👍").success?
    assert_equal 0, Community::Reaction.where(user: @reactor).count
  end
end
