# frozen_string_literal: true

require "test_helper"

class ReactionScoreTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    r1 = create_user
    r2 = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: section, user: @author, title: "T", status: "published",
      last_posted_at: Time.current, last_post_user: @author, replies_count: 0
    )
    post = Community::Post.create!(topic: topic, user: @author, floor_number: 1, body: "p", status: "published")
    Community::Reaction.create!(user: r1, post: post, emoji: "👍")
    Community::Reaction.create!(user: r2, post: post, emoji: "❤️")
  end

  test "defaults to a flat count when no weights are configured" do
    assert_equal 2, Community::Reaction.score_for_user(@author)
  end

  test "applies configured per-emoji weights" do
    SiteSetting.set("forum.reaction_scores", "👍:1,❤️:3")
    assert_equal 4, Community::Reaction.score_for_user(@author)
  end

  test "unlisted emoji still count as one" do
    SiteSetting.set("forum.reaction_scores", "❤️:3")
    assert_equal 4, Community::Reaction.score_for_user(@author)
  end
end
