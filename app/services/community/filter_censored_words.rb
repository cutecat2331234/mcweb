# frozen_string_literal: true

module Community
  class FilterCensoredWords < ApplicationService
    def initialize(text:)
      @text = text.to_s
    end

    def call
      filtered = @text.dup
      censored_words.each do |entry|
        pattern = Regexp.new(Regexp.escape(entry.word), Regexp::IGNORECASE)
        filtered = filtered.gsub(pattern, entry.replacement)
      end
      ServiceResult.success(filtered)
    end

    private

    def censored_words
      Rails.cache.fetch("forum/censored_words", expires_in: 5.minutes) do
        Community::CensoredWord.ordered.to_a
      end
    end
  end
end
