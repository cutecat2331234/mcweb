# frozen_string_literal: true

module Community
  class FetchUserOnebox < ApplicationService
    USER_PATH = %r{\A(?:/app)?/forum/users/([\w-]+)\z}i

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      path = if @url.start_with?("/")
               @url
      else
               URI.parse(@url).path
      end
      return ServiceResult.success(nil) unless path

      match = path.match(USER_PATH)
      return ServiceResult.success(nil) unless match

      user = User.find_by(username: match[1])
      return ServiceResult.success(nil) unless user

      trust = Community::TrustLevel.level_info(user)
      posts_count = Community::Post.where(user: user, status: :published).count

      ServiceResult.success(
        username: user.username,
        display_name: user.display_name.presence || user.username,
        avatar_url: user.avatar_url,
        trust_name: trust[:name],
        posts_count: posts_count,
        url: "/app/forum/users/#{user.username}"
      )
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end
  end
end
