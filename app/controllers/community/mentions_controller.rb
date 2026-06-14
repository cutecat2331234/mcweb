# frozen_string_literal: true

module Community
  class MentionsController < ApplicationController
    before_action :require_login

    def search
      q = params[:q].to_s.strip
      return render json: { users: [] } if q.length < 2

      pattern = "#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      blocked_ids = Community::UserBlock.where(blocker: current_user).select(:blocked_id)
      blocked_by_ids = Community::UserBlock.where(blocked: current_user).select(:blocker_id)

      users = User
        .where("username ILIKE :q OR display_name ILIKE :q", q: pattern)
        .where.not(id: current_user.id)
        .where.not(id: blocked_ids)
        .where.not(id: blocked_by_ids)
        .order(:username)
        .limit(8)

      render json: {
        users: users.map do |u|
          {
            username: u.username,
            display_name: u.display_name,
            avatar_url: u.avatar_url
          }
        end
      }
    end
  end
end
