# frozen_string_literal: true

module Api
  module V1
    class UsersController < BaseController
      include Serialization

      skip_before_action :require_read_scope!, only: :follow
      before_action :require_writer!, only: :follow

      # POST /api/v1/users/:id/follow  (write scope) — toggles following the user
      def follow
        target = User.find_by!(public_id: params[:id])
        result = Community::ToggleUserFollow.call(follower: api_user, followed_username: target.username)
        return render_service_error(result) if result.failure?

        render json: { data: { user_id: target.public_id, following: result.value[:following] } }
      end

      # GET /api/v1/users?q=<name>&sort=<posts|newest|username>
      def index
        scope = User.where(deleted_at: nil, status: "active")
        scope = scope.where("username ILIKE ?", "%#{params[:q]}%") if params[:q].present?
        scope = case params[:sort]
        when "posts" then scope.order(forum_posts_count: :desc)
        when "username" then scope.order(:username)
        else scope.order(created_at: :desc)
        end

        pagy, users = api_paginate(scope)
        render json: {
          data: users.map { |u| serialize_user(u) },
          meta: pagination_meta(pagy)
        }
      end

      # GET /api/v1/users/:id  (id = user public_id)
      def show
        user = User.find_by!(public_id: params[:id])
        raise ActiveRecord::RecordNotFound if user.deleted_at.present?

        render json: { data: serialize_user(user) }
      end
    end
  end
end
