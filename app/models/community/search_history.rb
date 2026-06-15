# frozen_string_literal: true

module Community
  class SearchHistory < ApplicationRecord
    self.table_name = "forum_search_histories"

    LIMIT = 20

    belongs_to :user

    scope :recent, -> { order(updated_at: :desc) }

    before_validation :assign_fingerprint

    def self.record!(user:, query:, filters: {})
      normalized_query = query.to_s.strip
      normalized_filters = filters.stringify_keys.compact
      return if normalized_query.blank? && normalized_filters.except("q").blank?

      fingerprint = SearchHistoryFingerprint.generate(query: normalized_query, filters: normalized_filters)
      existing = user.forum_search_histories.find_by(fingerprint: fingerprint)
      if existing
        existing.update!(query: normalized_query, filters: normalized_filters, updated_at: Time.current)
        return existing
      end

      entry = user.forum_search_histories.create!(query: normalized_query, filters: normalized_filters, fingerprint: fingerprint)
      trim_for_user!(user)
      entry
    end

    def self.trim_for_user!(user)
      ids_to_delete = user.forum_search_histories.recent.pluck(:id).drop(LIMIT)
      where(id: ids_to_delete).delete_all if ids_to_delete.any?
    end

    def url_params
      Community::SavedSearchPresenter.url_params(
        Struct.new(:query, :filters, keyword_init: true).new(query: query, filters: filters)
      )
    end

    def rss_params
      url_params.stringify_keys
    end

  private

    def assign_fingerprint
      self.fingerprint = SearchHistoryFingerprint.generate(query: query, filters: filters || {})
    end
  end
end
