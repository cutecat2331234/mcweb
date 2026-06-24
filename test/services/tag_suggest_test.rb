# frozen_string_literal: true

require "test_helper"

class TagSuggestTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "suggests tags matching the query by name or slug" do
    Community::Tag.create!(name: "Redstone", slug: "redstone-#{SecureRandom.hex(2)}", staff_only: false)
    Community::Tag.create!(name: "Building", slug: "building-#{SecureRandom.hex(2)}", staff_only: false)

    get forum_tag_suggest_path(q: "redstone")
    assert_response :success

    tags = JSON.parse(response.body)["tags"]
    assert_includes tags.map { |t| t["name"] }, "Redstone"
    assert_not_includes tags.map { |t| t["name"] }, "Building"
    assert tags.first["slug"].present?
  end

  test "returns empty for a blank query" do
    get forum_tag_suggest_path(q: "")
    assert_response :success
    assert_equal [], JSON.parse(response.body)["tags"]
  end
end
