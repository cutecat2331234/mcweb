# frozen_string_literal: true

module Api
  module V1
    # The bound user's bookmarks. Requires a bound user.
    class BookmarksController < BaseController
      include Serialization
      include ForumVisibility
      before_action :require_bound_user!

      # GET /api/v1/bookmarks
      def index
        scope = Community::Bookmark
          .where(user: api_user)
          .joins(:topic)
          .merge(visible_topics_scope)
          .includes(:post, topic: %i[user section])
          .order(Community::Bookmark.arel_table[:created_at].desc)
        pagy, bookmarks = api_paginate(scope)
        render json: {
          data: bookmarks.filter_map do |bookmark|
            next unless bookmark.topic
            if bookmark.post &&
               !Community::ForumAccess.public_api_post_visible?(post: bookmark.post, user: api_user)
              next
            end

            serialize_bookmark(bookmark)
          end,
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
