# frozen_string_literal: true

module Community
  class SearchRssToken
    InvalidToken = Class.new(StandardError)
    PURPOSE = "forum_search_rss"

    PERMITTED_KEYS = %w[
      q section category author tag solved locked pinned wiki featured announcement
      unlisted archived assigned assignee mine scope poll noreplies images
      created_after created_before topic_sort title_only posts_only
    ].freeze

    def self.normalize(params)
      source = params.stringify_keys
      PERMITTED_KEYS.index_with { |key| source[key].to_s.presence }.compact
    end

    def self.generate(params)
      Rails.application.message_verifier(PURPOSE).generate(normalize(params))
    end

    def self.verify(token)
      payload = Rails.application.message_verifier(PURPOSE).verify(token)
      raise InvalidToken unless payload.is_a?(Hash)

      payload.stringify_keys.slice(*PERMITTED_KEYS).compact
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidToken
    end
  end
end
