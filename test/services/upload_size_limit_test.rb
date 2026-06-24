# frozen_string_literal: true

require "test_helper"

class UploadSizeLimitTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    # Publishing a topic raises the user's trust level enough to unlock uploads.
    Community::CreateTopic.call(user: @user, section: section, title: "Unlock uploads", body: "opening post body", ip_address: "127.0.0.1")
    sign_in_as(@user)
  end

  test "rejects an upload larger than the configured limit" do
    SiteSetting.set("forum.max_upload_size_mb", "1")
    big = Tempfile.new([ "big", ".png" ])
    begin
      big.binmode
      big.write("x" * (1.megabyte + 50_000))
      big.rewind
      upload = Rack::Test::UploadedFile.new(big.path, "image/png")

      post forum_uploads_path, params: { file: upload }
      assert_response :unprocessable_entity
      assert_match(/1MB/, response.body)
    ensure
      big.close
      big.unlink
    end
  end
end
