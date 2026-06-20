# frozen_string_literal: true

module Community
  class SplitTopic < ApplicationService
    def initialize(user:, topic:, post:, title: nil, section: nil)
      @user = user
      @topic = topic
      @post = post
      @title = title.to_s.strip.presence
      @section = section
    end

    def call
      unless @user.permission?("forum.topics.move") || @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "You are not authorized to split topics.")
      end

      return ServiceResult.failure(error: "Cannot split the opening post.") if @post.floor_number <= 1
      return ServiceResult.failure(error: "Post does not belong to this topic.") if @post.forum_topic_id != @topic.id

      new_topic = nil
      Community::Topic.transaction do
        posts_to_move = @topic.posts.where("floor_number >= ?", @post.floor_number).order(:floor_number)
        split_title = @title || I18n.t("mcweb.forum.split_topic.default_title", title: @topic.title).truncate(120)
        target_section = @section || @topic.section

        new_topic = Community::Topic.create!(
          section: target_section,
          user: @post.user,
          title: split_title,
          prefix: @topic.prefix,
          status: :published,
          last_posted_at: Time.current,
          last_post_user: @post.user,
          replies_count: [ posts_to_move.count - 1, 0 ].max
        )

        staying_post_ids = @topic.posts.where("floor_number < ?", @post.floor_number).pluck(:id)

        posts_to_move.each_with_index do |moved_post, index|
          updates = { topic: new_topic, floor_number: index + 1 }
          if moved_post.parent_post_id.present? && staying_post_ids.include?(moved_post.parent_post_id)
            updates[:parent_post_id] = nil
          end
          moved_post.update!(updates)
        end

        if @topic.solved_post_id.present? && posts_to_move.exists?(id: @topic.solved_post_id)
          @topic.update!(solved_post_id: nil)
        end

        Community::SyncTopicLastPost.call(topic: @topic)
        Community::SyncTopicLastPost.call(topic: new_topic)
      end

      ServiceResult.success(new_topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
