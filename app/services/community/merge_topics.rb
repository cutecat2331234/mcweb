# frozen_string_literal: true

module Community
  class MergeTopics < ApplicationService
    def initialize(user:, source:, target_public_id:)
      @user = user
      @source = source
      @target_public_id = target_public_id.to_s.strip
    end

    def call
      unless @user.permission?("forum.topics.move") || @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "You are not authorized to merge topics.")
      end

      target = Community::Topic.find_by(public_id: @target_public_id, status: :published)
      return ServiceResult.failure(error: "Target topic not found.") unless target
      return ServiceResult.failure(error: "Cannot merge a topic into itself.") if @source.id == target.id

      Community::Topic.transaction do
        posts_to_move = @source.posts.order(:floor_number).offset(1)
        # Include soft-deleted posts: the unique [forum_topic_id, floor_number] index
        # covers discarded rows too, so reassigned floors must clear them or save! fails.
        next_floor = target.posts.with_discarded.maximum(:floor_number).to_i

        posts_to_move.each_with_index do |post, index|
          post.update!(topic: target, floor_number: next_floor + index + 1)
        end

        @source.update!(status: :hidden, locked: true)
        Community::SyncTopicLastPost.call(topic: target)
      end

      Administration::AuditLogger.call(
        actor: @user,
        action: "forum.topics.merge",
        resource: target,
        metadata: { source_topic: @source.public_id, target_topic: target.public_id }
      )
      ServiceResult.success(target)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
