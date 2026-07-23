# frozen_string_literal: true

module Api
  module V1
    class PostsController < BaseController
      include Serialization
      include ForumVisibility

      skip_before_action :require_read_scope!, only: :create
      before_action :require_writer!, only: :create

      # GET /api/v1/posts/:id  (id = post primary id)
      def show
        post = Community::Post.includes(:user, :topic).find(params[:id])
        topic = post.topic
        unless post.status == "published" && post.post_type != "whisper" &&
               topic&.status == "published" && section_visible?(topic.section)
          raise ActiveRecord::RecordNotFound
        end

        render json: { data: serialize_post(post) }
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
          ip_address: request.remote_ip
        )
        return render_service_error(result) if result.failure?

        render json: { data: serialize_post(result.value) }, status: :created
      end

      private

      def find_optional_post(id)
        return nil if id.blank?

        Community::Post.find_by(id: id)
      end
    end
  end
end
