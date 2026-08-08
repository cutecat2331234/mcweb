# frozen_string_literal: true

module Website
  class HomeCache
    VERSION_KEY = "website/home/v1/version"
    ENTRY_NAMESPACE = "website/home/v1/entry"
    TTL = 2.minutes

    class << self
      def fetch(locale:, feature_state:, &block)
        Rails.cache.fetch(
          [
            ENTRY_NAMESPACE,
            version,
            locale.to_s,
            feature_state.to_h.sort
          ],
          expires_in: TTL,
          &block
        )
      end

      def bump!
        Rails.cache.write(VERSION_KEY, version + 1)
      end

      def version
        Rails.cache.fetch(VERSION_KEY) { 1 }.to_i
      end
    end
  end
end
