# frozen_string_literal: true

module Community
  class PrepareProfileWallBody < ApplicationService
    def initialize(author:, body:, max_length:)
      @author = author
      @body = body.to_s.strip
      @max_length = max_length
    end

    def call
      return failure("profile_post_blank") if @body.blank?
      return failure("profile_post_too_long") if @body.length > @max_length

      post_restriction = Community::CheckWarningRestrictions.call(user: @author, action: :post)
      return post_restriction if post_restriction.failure?

      if Community::TrustLevel.contains_link?(@body)
        link_restriction = Community::CheckWarningRestrictions.call(user: @author, action: :link)
        return link_restriction if link_restriction.failure?
        return failure("new_members_cannot_post_links") unless Community::TrustLevel.can_post_links?(@author)
      end

      Community::FilterCensoredWords.call(text: @body)
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
