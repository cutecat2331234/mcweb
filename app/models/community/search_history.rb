# frozen_string_literal: true

module Community
  class SearchHistory < ApplicationRecord
    self.table_name = "forum_search_histories"

    LIMIT = 20

    belongs_to :user

    scope :recent, -> { order(created_at: :desc) }

    def self.record!(user:, query:, filters: {})
      normalized_query = query.to_s.strip
      normalized_filters = filters.stringify_keys.compact
      return if normalized_query.blank? && normalized_filters.except("q").blank?

      existing = user.forum_search_histories.recent.find_by(query: normalized_query, filters: normalized_filters)
      if existing
        existing.touch
        return existing
      end

      entry = user.forum_search_histories.create!(query: normalized_query, filters: normalized_filters)
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
  end
end
