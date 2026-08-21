# frozen_string_literal: true

require "test_helper"
require "chunky_png"

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
    assert_equal "头像不是有效的 JPEG 或 PNG 图片。", flash[:alert]
    assert_not @user.reload.forum_avatar.attached?
  end

  test "rejects markup disguised as an image without creating a blob" do
    before_count = ActiveStorage::Blob.count

    patch forum_user_path(@user.username), params: {
      user: {
        forum_avatar: Rack::Test::UploadedFile.new(
          StringIO.new("\x89PNG\r\n\x1A\n<script>alert(1)</script>".b),
          "image/png",
          original_filename: "avatar.png"
        )
      }
    }

    assert_redirected_to forum_user_path(@user.username)
    assert_equal "头像不是有效的 JPEG 或 PNG 图片。", flash[:alert]
    assert_equal before_count, ActiveStorage::Blob.count
    assert_not @user.reload.forum_avatar.attached?
  end

  test "derives avatar type from decoded bytes and stores only normalized image data" do
    source = ChunkyPNG::Image.new(3, 2, ChunkyPNG::Color.rgb(20, 90, 180)).to_blob

    patch forum_user_path(@user.username), params: {
      user: {
        forum_avatar: Rack::Test::UploadedFile.new(
          StringIO.new(source),
          "text/html",
          original_filename: "avatar.php"
        )
      }
    }

    assert_redirected_to forum_user_path(@user.username)
    assert_equal I18n.t("mcweb.flash.avatar_updated"), flash[:notice]
    attachment = @user.reload.forum_avatar
    assert_predicate attachment, :attached?
    assert_equal "image/png", attachment.blob.content_type
    assert_equal "avatar.png", attachment.blob.filename.to_s
    decoded = ChunkyPNG::Image.from_blob(attachment.download)
    assert_equal [ 3, 2 ], [ decoded.width, decoded.height ]
  end
end
