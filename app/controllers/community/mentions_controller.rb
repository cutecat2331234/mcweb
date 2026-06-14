# frozen_string_literal: true

module Community
  class MentionsController < ApplicationController
    before_action :require_login

    def search
      q = params[:q].to_s.strip
      return render json: { users: [] } if q.length < 2

      users = User.where("username ILIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(q)}%")
        .where.not(id: current_user.id)
        .limit(8)

      render json: {
        users: users.map { |u| { username: u.username, avatar_url: u.avatar_url } }
      }
    end
  end
end
