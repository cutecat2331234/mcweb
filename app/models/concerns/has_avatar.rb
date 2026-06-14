# frozen_string_literal: true

module HasAvatar
  extend ActiveSupport::Concern

  included do
    has_one_attached :forum_avatar if respond_to?(:has_one_attached)
  end

  def avatar_url(size: 48)
    if respond_to?(:forum_avatar) && forum_avatar.attached?
      return Rails.application.routes.url_helpers.rails_blob_path(forum_avatar, only_path: true)
    end

    hash = Digest::MD5.hexdigest(email.to_s.strip.downcase)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
  end
end
