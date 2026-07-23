# frozen_string_literal: true

require "test_helper"

class Community::ReactionTypeModelTest < ActiveSupport::TestCase
  test "configured? is false when no active types exist" do
    assert_not Community::ReactionType.configured?
  end

  test "emojis returns active types in order" do
    Community::ReactionType.create!(emoji: "👍", name: "Like", position: 1, active: true)
    Community::ReactionType.create!(emoji: "❤️", name: "Love", position: 0, active: true)
    Community::ReactionType.create!(emoji: "😡", name: "Angry", position: 2, active: false)

    assert Community::ReactionType.configured?
    assert_equal %w[❤️ 👍], Community::ReactionType.emojis
  end

  test "score_map maps active emoji to score" do
    Community::ReactionType.create!(emoji: "👍", name: "Like", score: 1, active: true)
    Community::ReactionType.create!(emoji: "💎", name: "Gem", score: 5, active: true)

    assert_equal({ "👍" => 1, "💎" => 5 }, Community::ReactionType.score_map)
  end
end

class Community::ReactionTypeWiringTest < ActiveSupport::TestCase
  test "ToggleReaction.allowed_emoji falls back to defaults when not configured" do
    SiteSetting.set("forum.reaction_emojis", "")
    assert_equal Community::ToggleReaction::ALLOWED_EMOJI, Community::ToggleReaction.allowed_emoji
  end

  test "ToggleReaction.allowed_emoji prefers managed reaction types" do
    Community::ReactionType.create!(emoji: "🔥", name: "Fire", position: 0, active: true)
    Community::ReactionType.create!(emoji: "💯", name: "Hundred", position: 1, active: true)

    assert_equal %w[🔥 💯], Community::ToggleReaction.allowed_emoji
  end

  test "Reaction.score_map prefers managed reaction types" do
    Community::ReactionType.create!(emoji: "🔥", name: "Fire", score: 3, active: true)
    assert_equal({ "🔥" => 3 }, Community::Reaction.score_map)
  end

  test "managed reaction emoji is accepted by ToggleReaction" do
    Community::ReactionType.create!(emoji: "🔥", name: "Fire", score: 3, active: true)
    category = Community::Category.find_or_create_by!(slug: "rt-cat") { |c| c.name = "RT" }
    section = Community::Section.find_or_create_by!(category: category, slug: "rt-sec") do |s|
      s.name = "RT Section"
      s.position = 0
    end
    author = create_user(username: "rtauthor")
    reactor = create_user(username: "rtreactor")
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}", section: section, user: author,
      title: "RT topic", status: "published", last_posted_at: Time.current, last_post_user: author, replies_count: 0
    )
    post = Community::Post.create!(topic: topic, user: author, floor_number: 1, body: "OP", status: "published")

    result = Community::ToggleReaction.call(user: reactor, post: post, emoji: "🔥")
    assert result.success?
    assert result.value[:added]
  end
end

class Community::ReactionTypesAdminTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "forum.sections.manage")
    grant_admin_module(@admin, "forum")
    sign_in_as(@admin)
  end

  test "admin can create, update and delete a reaction type" do
    assert_difference -> { Community::ReactionType.count }, 1 do
      post admin_forum_reaction_types_path, params: {
        reaction_type: { emoji: "🎯", name: "Bullseye", score: 2, position: 0, active: true }
      }
    end
    assert_redirected_to admin_forum_reaction_types_path
    rt = Community::ReactionType.find_by(emoji: "🎯")
    assert_equal "Bullseye", rt.name

    patch admin_forum_reaction_type_path(rt), params: {
      reaction_type: { emoji: "🎯", name: "Target", score: 4, position: 0, active: true }
    }
    assert_redirected_to admin_forum_reaction_types_path
    assert_equal "Target", rt.reload.name
    assert_equal 4, rt.score

    assert_difference -> { Community::ReactionType.count }, -1 do
      delete admin_forum_reaction_type_path(rt)
    end
  end

  test "index renders" do
    get admin_forum_reaction_types_path
    assert_response :success
  end
end
