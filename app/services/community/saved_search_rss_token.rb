# frozen_string_literal: true

module Community
  class SavedSearchRssToken
    InvalidToken = Class.new(StandardError)
    PURPOSE = "saved_search_rss"

    def self.generate(search)
      Rails.application.message_verifier(PURPOSE).generate(search.id, expires_in: 90.days)
    end

    def self.verify(token)
      Rails.application.message_verifier(PURPOSE).verify(token)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidToken
    end
  end
end
