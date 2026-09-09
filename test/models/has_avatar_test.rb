# frozen_string_literal: true

require "test_helper"

class HasAvatarTest < ActiveSupport::TestCase
  test "default avatars are local and do not disclose account identifiers" do
    user = User.new(email: "private-avatar@example.com")

    assert_equal "/avatars/default.svg", user.avatar_url
    assert_equal user.avatar_url, user.avatar_url(size: 96)
    assert_equal user.avatar_url, User.new(email: "another@example.com").avatar_url
    assert File.file?(Rails.root.join("public", user.avatar_url.delete_prefix("/")))
    refute_includes user.avatar_url, Digest::MD5.hexdigest(user.email)
  end

  test "uploaded avatars use a same-origin storage proxy instead of a storage redirect" do
    user = create_user
    File.open(Rails.root.join("public/icon.png"), "rb") do |image|
      user.forum_avatar.attach(io: image, filename: "avatar.png", content_type: "image/png")
    end

    assert_equal Rails.application.routes.url_helpers.rails_storage_proxy_path(
      user.forum_avatar,
      only_path: true
    ), user.avatar_url(size: 96)
    assert_match %r{\A/rails/active_storage/blobs/proxy/}, user.avatar_url
    refute_match %r{\A(?:https?:)?//}, user.avatar_url
  end
end
