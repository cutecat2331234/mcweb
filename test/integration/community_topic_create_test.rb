# frozen_string_literal: true

require "test_helper"

class CommunityTopicCreateTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @category = Community::Category.find_or_create_by!(slug: "topic-create-test") { |c| c.name = "Test" }
    @section = Community::Section.find_or_create_by!(category: @category, slug: "general") do |s|
      s.name = "General"
      s.description = "Test section"
      s.position = 0
    end
    sign_in_as(@user)
  end

  test "empty body returns validation errors in props" do
    post forum_topics_path(section_id: @section.slug), params: {
      topic: { title: "Test title", body: "" }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "form_errors"
    assert_includes response.body, "帖子内容过短"
  end
end
