# frozen_string_literal: true

module Api
  module V1
    class TopicsController < BaseController
      include Serialization
      include ForumVisibility

      # GET /api/v1/topics?section_id=<slug>&page=&limit=
      def index
        scope = visible_topics_scope.includes(:user, :section, :tags)

        if params[:section_id].present?
          section = Community::Section.find_by(slug: params[:section_id])
          raise ActiveRecord::RecordNotFound unless section && section_visible?(section)

          scope = scope.where(forum_section_id: section.id)
        end

        scope = scope.order(pinned: :desc, last_posted_at: :desc)
        pagy, topics = api_paginate(scope)

        render json: {
          data: topics.map { |topic| serialize_topic(topic) },
          meta: pagination_meta(pagy)
        }
      end

      # GET /api/v1/topics/:id  (id = topic public_id); includes paginated posts
      def show
        topic = find_visible_topic!(params[:id])
        topic.class.increment_counter(:views_count, topic.id) if params[:count_view] == "true"

        pagy, posts = api_paginate(visible_posts_scope(topic).includes(:user, :topic))

        render json: {
          data: serialize_topic(topic).merge(posts: posts.map { |post| serialize_post(post) }),
          meta: pagination_meta(pagy)
        }
      end
    end
  end
end
