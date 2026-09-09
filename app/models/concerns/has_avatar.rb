# frozen_string_literal: true

module HasAvatar
  extend ActiveSupport::Concern

  DEFAULT_AVATAR_PATH = "/avatars/default.svg"

  included do
    has_one_attached :forum_avatar if respond_to?(:has_one_attached)
  end

  def avatar_url(size: 48)
    if respond_to?(:forum_avatar) && forum_avatar.attached?
      # Proxy uploaded avatars through this origin even when blob storage is
      # remote. A redirecting blob URL would expose every reader to that host.
      return Rails.application.routes.url_helpers.rails_storage_proxy_path(forum_avatar, only_path: true)
    end

    # Keep the size keyword for callers; the local SVG scales without revealing
    # an email hash or requiring an external avatar service on every page.
    DEFAULT_AVATAR_PATH
  end
end
