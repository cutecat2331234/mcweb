# frozen_string_literal: true

module Api
  module V1
    class PostsController < BaseController
      include Serialization
      include ForumVisibility

      skip_before_action :require_read_scope!, only: %i[create react]
      before_action :require_writer!, only: %i[create react]

      # GET /api/v1/posts/:id  (id = post primary id)
      def show
        render json: { data: serialize_post(load_visible_post!(params[:id])) }
      end

      # GET /api/v1/posts/:id/reactions — reaction counts + allowed emoji
      def reactions
        post = load_visible_post!(params[:id])
        render json: {
          data: {
            post_id: post.id,
            counts: post.reactions.group(:emoji).count,
            allowed: Community::ToggleReaction.allowed_emoji
          }
        }
      end

      # POST /api/v1/posts/:id/reactions  (write scope) — toggle a reaction
      # params: emoji
      def react
        post = load_visible_post!(params[:id])
        result = Community::ToggleReaction.call(
          user: api_user,
          post: post,
          emoji: params[:emoji].to_s,
          ip_address: request.remote_ip
        )
        return render_service_error(result) if result.failure?

        render json: { data: { post_id: post.id, added: result.value[:added], counts: result.value[:counts] } }
      end

      # POST /api/v1/posts  (write scope; acts as the key's user)
      # params: topic_id (topic public_id), body, quoted_post_id, parent_post_id
      def create
        topic = find_visible_topic!(params[:topic_id])

        result = Community::CreatePost.call(
          user: api_user,
          topic: topic,
          body: params[:body].to_s,
          quoted_post: find_optional_post(params[:quoted_post_id]),
          parent_post: find_optional_post(params[:parent_post_id]),
          idempotency_key: request.headers["Idempotency-Key"].presence || params[:idempotency_key],
          ip_address: request.remote_ip
        )
        return render_service_error(result) if result.failure?

        response.set_header("Idempotency-Key", request.headers["Idempotency-Key"]) if request.headers["Idempotency-Key"].present?
        render json: { data: serialize_post(result.value) }, status: :created
      end

      private

      def load_visible_post!(id)
        post = Community::Post.includes(:user, :topic).find(id)
        visible = Community::ForumAccess.public_api_post_visible?(
          post: post,
          user: api_user
        )
        raise ActiveRecord::RecordNotFound unless visible

        post
      end

      def find_optional_post(id)
        return nil if id.blank?

        Community::Post.find_by(id: id)
      end
    end
  end
end
