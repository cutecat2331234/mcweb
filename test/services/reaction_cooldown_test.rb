# frozen_string_literal: true

require "test_helper"

class ReactionCooldownTest < ActiveSupport::TestCase
  setup do
    @reactor = create_user
    author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    @posts = Array.new(3) do |i|
      topic = Community::Topic.create!(
        public_id: "t_#{SecureRandom.alphanumeric(10)}",
        section: section, user: author, title: "T#{i}", status: "published",
        last_posted_at: Time.current, last_post_user: author, replies_count: 0
      )
      Community::Post.create!(topic: topic, user: author, floor_number: 1, body: "post #{i}", status: "published")
    end
  end

  test "enforces a per-minute reaction burst limit" do
    SiteSetting.set("forum.max_reactions_per_minute", "2")
    assert Community::ToggleReaction.call(user: @reactor, post: @posts[0], emoji: "👍").success?
    assert Community::ToggleReaction.call(user: @reactor, post: @posts[1], emoji: "👍").success?

    third = Community::ToggleReaction.call(user: @reactor, post: @posts[2], emoji: "👍")
    assert third.failure?
    assert_equal 2, Community::Reaction.where(user: @reactor).count
  end

  test "is off by default" do
    @posts.each { |p| assert Community::ToggleReaction.call(user: @reactor, post: p, emoji: "👍").success? }
  end
end
