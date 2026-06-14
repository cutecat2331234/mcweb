# frozen_string_literal: true

module Community
  class MembersController < ApplicationController
    def index
      scope = User.where(status: :active)
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        scope = scope.where("username ILIKE ? OR display_name ILIKE ?", q, q)
      end

      sort = params[:sort].to_s
      scope = case sort
              when "joined"
                scope.order(created_at: :desc)
              else
                scope.order(Arel.sql("last_seen_at DESC NULLS LAST, created_at DESC"))
              end

      @pagy, members = pagy(scope, limit: 30)

      render inertia: "Community/Members/Index", props: {
        members: members.map { |user| serialize_member(user) },
        pagination: pagy_props(@pagy),
        query: params[:q].to_s,
        sort: sort.presence || "active"
      }
    end

    private

    def serialize_member(user)
      {
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        profile_url: forum_user_path(user.username),
        last_seen_at: user.last_seen_at ? l(user.last_seen_at, format: :short) : nil,
        online: user.last_seen_at && user.last_seen_at > 5.minutes.ago,
        posts_count: Community::Post.where(user: user, status: :published).count,
        member_since: l(user.created_at, format: :short)
      }
    end
  end
end
