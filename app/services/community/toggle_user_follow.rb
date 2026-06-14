# frozen_string_literal: true

module Community
  class ToggleUserFollow < ApplicationService
    def initialize(follower:, followed_username:)
      @follower = follower
      @followed_username = followed_username.to_s.strip
    end

    def call
      followed = User.find_by!(username: @followed_username)
      return ServiceResult.failure(error: "Cannot follow yourself.") if @follower.id == followed.id

      existing = Community::UserFollow.find_by(follower: @follower, followed: followed)
      if existing
        existing.destroy!
        ServiceResult.success(following: false)
      else
        Community::UserFollow.create!(follower: @follower, followed: followed)
        ServiceResult.success(following: true)
      end
    rescue ActiveRecord::RecordNotFound
      ServiceResult.failure(error: "User not found.")
    end
  end
end
