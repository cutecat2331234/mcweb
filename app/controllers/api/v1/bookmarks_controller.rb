# frozen_string_literal: true

module Api
  module V1
    # The bound user's bookmarks. Requires a bound user.
    class BookmarksController < BaseController
      include Serialization
      before_action :require_bound_user!

      # GET /api/v1/bookmarks
      def index
        scope = Community::Bookmark.where(user: api_user).includes(topic: %i[user section]).order(created_at: :desc)
        pagy, bookmarks = api_paginate(scope)
        render json: {
          data: bookmarks.filter_map { |b| b.topic && serialize_bookmark(b) },
          meta: pagination_meta(pagy)
        }
      end

      private

      def serialize_bookmark(bookmark)
        {
          id: bookmark.id,
          post_id: bookmark.forum_post_id,
          created_at: bookmark.created_at&.iso8601,
          topic: serialize_topic(bookmark.topic)
        }
      end
    end
  end
end
