# frozen_string_literal: true

module Api
  module V1
    class PostsController < BaseController
      include Serialization
      include ForumVisibility

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
    end
  end
end
