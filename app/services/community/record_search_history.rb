# frozen_string_literal: true

module Community
  class RecordSearchHistory < ApplicationService
    FILTER_KEYS = %w[
      section category author tag solved locked pinned wiki featured announcement
      unlisted archived assigned assignee mine scope poll noreplies images
      created_after created_before topic_sort title_only posts_only
    ].freeze

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def call
      return ServiceResult.success(skipped: true) if @user.blank?

      query = @params[:q].to_s.strip
      filters = FILTER_KEYS.index_with { |key| @params[key].to_s.presence }.compact
      entry = Community::SearchHistory.record!(user: @user, query: query, filters: filters)
      ServiceResult.success(entry: entry)
    end
  end
end
