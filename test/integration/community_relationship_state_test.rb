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
        put relationship[:path], params: { expected_revision: "0" }
        assert_response :see_other
      end
      assert_equal 1, relationship[:model].where(relationship[:attributes]).count

      2.times do
        delete relationship[:path], params: { expected_revision: "1" }
        assert_response :see_other
      end
      assert_not relationship[:model].where(relationship[:attributes]).exists?

      post relationship[:path]
      assert_response :not_found
      assert_not relationship[:model].where(relationship[:attributes]).exists?
    end
  end

  test "JSON mutations return confirmed state and timeout retries do not reverse later choices" do
    relationships.each do |relationship|
      path = relationship[:path]
      put path, params: { expected_revision: "0" }, as: :json
      assert_response :success
      assert_equal true, response.parsed_body.dig("data", "active")
      assert_equal "1", response.parsed_body.dig("data", "revision")
      assert_includes response.headers["Cache-Control"], "no-store"

      delete path, params: { expected_revision: "1" }, as: :json # response lost in transit
      assert_response :success
      assert_equal false, response.parsed_body.dig("data", "active")
      put path, params: { expected_revision: "2" }, as: :json
      assert_response :success

      2.times do
        delete path, params: { expected_revision: "1" }, as: :json
        assert_response :conflict
        assert_equal true, response.parsed_body.dig("data", "active")
        assert_equal "3", response.parsed_body.dig("data", "revision")
        assert_equal 1, relationship[:model].where(relationship[:attributes]).count
      end

      delete path, params: { expected_revision: "3" }, as: :json
      assert_response :success
      put path, params: { expected_revision: "2" }, as: :json
      assert_response :conflict
      assert_equal false, response.parsed_body.dig("data", "active")
      assert_equal "4", response.parsed_body.dig("data", "revision")
    end
  end

  test "unversioned legacy writes and POST fail closed while relationships are active" do
    relationships.each do |relationship|
      relationship[:model].create!(relationship[:attributes])
      [ :put, :delete ].each do |method|
        public_send(method, relationship[:path], as: :json)
        assert_response 428
        assert_equal "precondition_required", response.parsed_body["error"]
        assert_equal true, response.parsed_body.dig("data", "active")
        assert_equal "0", response.parsed_body.dig("data", "revision")
      end
      post relationship[:path]
      assert_response :not_found
      assert_equal 1, relationship[:model].where(relationship[:attributes]).count
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
