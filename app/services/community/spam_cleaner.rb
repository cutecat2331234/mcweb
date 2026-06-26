# frozen_string_literal: true

module Community
  # XenForo-style "spam cleaner": soft-delete a user's forum content and ban them.
  # Soft-deletes are reversible (deleted_at) and the action is audited with counts.
  class SpamCleaner < ApplicationService
    def initialize(actor:, user:, ban: true)
      @actor = actor
      @user = user
      @ban = ban
    end

    def call
      unless @actor.permission?("forum.users.warn") || @actor.permission?("admin.access")
        return ServiceResult.failure(error: "You are not authorized to run the spam cleaner.")
      end
      if @user.account_owner? || @user.id == @actor.id
        return ServiceResult.failure(error: "This user cannot be cleaned.")
      end

      topics_count = 0
      posts_count = 0
      ActiveRecord::Base.transaction do
        posts = Community::Post.where(user_id: @user.id)
        posts_count = posts.count
        posts.find_each(&:soft_delete!)

        topics = Community::Topic.where(user_id: @user.id)
        topics_count = topics.count
        topics.find_each(&:soft_delete!)
      end

      Administration::BanUser.call(user: @user, actor: @actor, reason: "Spam cleanup") if @ban

      Administration::AuditLogger.call(
        actor: @actor,
        action: "forum.spam_cleanup",
        resource: @user,
        metadata: { topics: topics_count, posts: posts_count, banned: @ban }
      )

      ServiceResult.success(topics: topics_count, posts: posts_count)
    end
  end
end
