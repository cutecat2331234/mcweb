# frozen_string_literal: true

module Api
  module V1
    class TopicsController < BaseController
      include Serialization
      include ForumVisibility

      skip_before_action :require_read_scope!, only: %i[create bookmark subscription solve unsolve]
      before_action :require_writer!, only: %i[create bookmark subscription solve unsolve]

      # GET /api/v1/topics?section_id=<slug>&page=&limit=
      def index
        scope = visible_topics_scope.includes(:user, :section, :tags, :topic_field_values)

        if params[:section_id].present?
          section = Community::Section.find_by(slug: params[:section_id])
          raise ActiveRecord::RecordNotFound unless section && section_visible?(section)

          scope = scope.where(forum_section_id: section.id)
        end

        if params[:q].present?
          scope = scope.where(
            "to_tsvector('simple', coalesce(forum_topics.title, '')) @@ plainto_tsquery('simple', ?)",
            params[:q].to_s
          )
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

      # POST /api/v1/topics  (write scope; acts as the key's user)
      # params: section_id (slug), title, body, tag_names[], prefix
      def create
        permitted = topic_create_params
        section = Community::Section.find_by!(slug: permitted[:section_id])

        result = Community::CreateTopic.call(
          user: api_user,
          section: section,
          title: permitted[:title].to_s,
          body: permitted[:body].to_s,
          tag_names: permitted[:tag_names],
          prefix: permitted[:prefix],
          custom_fields: permitted[:custom_fields],
          ip_address: request.remote_ip
        )
        return render_service_error(result) if result.failure?

        render json: { data: serialize_topic(result.value) }, status: :created
      end

      # POST /api/v1/topics/:id/bookmark  (write scope) — toggles a topic bookmark
      def bookmark
        topic = find_visible_topic!(params[:id])
        result = Community::ToggleBookmark.call(user: api_user, topic: topic)
        render json: { data: { topic_id: topic.public_id, bookmarked: result.value[:bookmarked] } }
      end

      # POST /api/v1/topics/:id/subscription  (write scope) — set watch level
      # params: level = watching | tracking | normal | off
      def subscription
        topic = find_visible_topic!(params[:id])
        result = Community::SetSubscriptionLevel.call(user: api_user, subscribable: topic, level: params[:level].to_s)
        return render_service_error(result) if result.failure?

        render json: { data: { topic_id: topic.public_id, notification_level: result.value[:notification_level] } }
      end

      # POST /api/v1/topics/:id/solve  (write scope) — params: post_id (marked answer)
      def solve
        topic = find_visible_topic!(params[:id])
        post = topic.posts.find(params[:post_id])
        result = Community::MarkTopicSolved.call(user: api_user, topic: topic, post: post)
        return render_service_error(result) if result.failure?

        render json: { data: { topic_id: topic.public_id, solved_post_id: post.id } }
      end

      # POST /api/v1/topics/:id/unsolve  (write scope)
      def unsolve
        topic = find_visible_topic!(params[:id])
        result = Community::UnsolveTopic.call(user: api_user, topic: topic)
        return render_service_error(result) if result.failure?

        render json: { data: { topic_id: topic.public_id, solved: false } }
      end

      private

      def topic_create_params
        params.permit(:section_id, :title, :body, :prefix, tag_names: [], custom_fields: {})
      end
    end
  end
end
