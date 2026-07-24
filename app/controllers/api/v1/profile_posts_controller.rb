# frozen_string_literal: true

module Api
  module V1
    # XenForo-style profile wall posts for a given user.
    class ProfilePostsController < BaseController
      include Serialization

      skip_before_action :require_read_scope!, only: :create
      before_action :require_writer!, only: :create
      before_action :set_profile_user

      # GET /api/v1/users/:user_id/profile-posts
      def index
        scope = Community::ProfilePost.where(profile_user: @profile_user).visible.recent
        pagy, posts = api_paginate(scope.includes(:author))
        render json: {
          data: posts.map { |p| serialize_profile_post(p) },
          meta: pagination_meta(pagy)
        }
      end

      # POST /api/v1/users/:user_id/profile-posts  (write scope)
      def create
        result = Community::CreateProfilePost.call(author: api_user, profile_user: @profile_user, body: params[:body].to_s)
        return render_service_error(result) if result.failure?

        render json: { data: serialize_profile_post(result.value) }, status: :created
      end

      private

      def set_profile_user
        @profile_user = User.find_by!(public_id: params[:user_id])
      end

      def serialize_profile_post(post)
        {
          id: post.id,
          body: post.body,
          author: serialize_user_ref(post.author),
          profile_user_id: @profile_user.public_id,
          created_at: post.created_at&.iso8601
        }
      end
    end
  end
end
