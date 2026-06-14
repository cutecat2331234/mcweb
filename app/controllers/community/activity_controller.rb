# frozen_string_literal: true

module Community
  class ActivityController < ApplicationController
    def index
      scope = Community::Post.where(status: :published)
        .includes(:user, topic: :section)
        .order(created_at: :desc)

      if logged_in?
        blocked_ids = blocked_user_ids
        scope = scope.where.not(user_id: blocked_ids) if blocked_ids.any?
      end

      @pagy, posts = pagy(scope, limit: 30)

      render inertia: "Community/Activity/Index", props: {
        posts: posts.map { |post| serialize_activity_post(post) },
        pagination: pagy_props(@pagy)
      }
    end
  end
end
