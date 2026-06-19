# frozen_string_literal: true

require "test_helper"

class CommunityUserProfileTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(username: "profileuser")
    sign_in_as(@user)
  end

  test "rejects invalid avatar upload with chinese message" do
    patch forum_user_path(@user.username), params: {
      user: {
        forum_avatar: Rack::Test::UploadedFile.new(
          StringIO.new("not an image"),
          "application/pdf",
          original_filename: "bad.pdf"
        )
      }
    }

    assert_redirected_to forum_user_path(@user.username)
    assert_equal "不支持的图片格式（仅支持 JPEG、PNG、GIF、WebP）。", flash[:alert]
  end
end
