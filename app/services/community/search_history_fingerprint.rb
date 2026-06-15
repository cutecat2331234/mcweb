# frozen_string_literal: true

module Community
  module SearchHistoryFingerprint
    module_function

    def generate(query:, filters: {})
      normalized_query = query.to_s.strip
      normalized_filters = filters.stringify_keys.compact.sort.to_h
      Digest::SHA256.hexdigest("#{normalized_query}|#{normalized_filters.to_json}")
    end
  end
end
