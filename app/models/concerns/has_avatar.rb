# frozen_string_literal: true

module HasAvatar
  extend ActiveSupport::Concern

  def avatar_url(size: 48)
    hash = Digest::MD5.hexdigest(email.to_s.strip.downcase)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
  end
end
