# frozen_string_literal: true

require "test_helper"

class CommunityRelationshipStateTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_user(username: "relationship_actor")
    @target = create_user(username: "relationship_target")
    sign_in_as(@actor)
  end

  test "web relationship endpoints are idempotent and legacy POST cannot mutate state" do
    relationships.each do |relationship|
      2.times do
        put relationship[:path]
        assert_response :see_other
      end
      assert_equal 1, relationship[:model].where(relationship[:attributes]).count

      2.times do
        delete relationship[:path]
        assert_response :see_other
      end
      assert_not relationship[:model].where(relationship[:attributes]).exists?

      post relationship[:path]
      assert_response :not_found
      assert_not relationship[:model].where(relationship[:attributes]).exists?
    end
  end

  private

  def relationships
    [
      {
        path: forum_block_user_path(@target.username),
        model: Community::UserBlock,
        attributes: { blocker: @actor, blocked: @target }
      },
      {
        path: forum_ignore_user_path(@target.username),
        model: Community::UserIgnore,
        attributes: { ignorer: @actor, ignored: @target }
      },
      {
        path: forum_user_follow_path(@target.username),
        model: Community::UserFollow,
        attributes: { follower: @actor, followed: @target }
      }
    ]
  end
end
