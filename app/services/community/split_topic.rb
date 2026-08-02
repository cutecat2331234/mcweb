# frozen_string_literal: true

module Community
  class SplitTopic < ApplicationService
    def initialize(user:, topic:, post:, title: nil, section: nil)
      @user = user
      @topic = topic
      @post = post
      @title = title.to_s.strip.presence
      @requested_section = section
      @section = section
    end

    def call
      unless @user.permission?("forum.topics.move") || @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: :you_are_not_authorized_to_split_topics)
      end

      return ServiceResult.failure(error: :cannot_split_the_opening_post) if @post.floor_number <= 1
      return ServiceResult.failure(error: :post_does_not_belong_to_this_topic) if @post.forum_topic_id != @topic.id

      new_topic = nil
      lock_attempts = 0
      begin
        Community::Topic.transaction do
          target_section = @requested_section || @topic.section
          @topic, _source_section, @section = Community::SectionHierarchyLock.lock_topic!(
            @topic,
            target_section
          )
          unless @section.publicly_active?
            return ServiceResult.failure(error: :destination_section_not_available)
          end

          @post.reload
          return ServiceResult.failure(error: :cannot_split_the_opening_post) if @post.floor_number <= 1
          return ServiceResult.failure(error: :post_does_not_belong_to_this_topic) if @post.forum_topic_id != @topic.id

          posts_to_move = Community::Post.with_discarded
            .where(forum_topic_id: @topic.id)
            .where("floor_number >= ?", @post.floor_number)
            .order(:floor_number)
            .to_a
          moved_post_ids = posts_to_move.map(&:id)
          split_title = @title || I18n.t("mcweb.forum.split_topic.default_title", title: @topic.title).truncate(120)

          new_topic = Community::Topic.create!(
            section: @section,
            user: @post.user,
            title: split_title,
            prefix: @topic.prefix,
            status: :published,
            last_posted_at: Time.current,
            last_post_user: @post.user,
            replies_count: 0
          )

          staying_post_ids = Community::Post.with_discarded
            .where(forum_topic_id: @topic.id)
            .where("floor_number < ?", @post.floor_number)
            .pluck(:id)

          posts_to_move.each_with_index do |moved_post, index|
            updates = { topic: new_topic, floor_number: index + 1 }
            if moved_post.parent_post_id.present? && staying_post_ids.include?(moved_post.parent_post_id)
              updates[:parent_post_id] = nil
            end
            moved_post.update!(updates)
          end

          if @topic.solved_post_id.present? && moved_post_ids.include?(@topic.solved_post_id)
            @topic.update!(solved_post_id: nil)
          end

          Community::SyncTopicLastPost.call(topic: @topic)
          Community::SyncTopicLastPost.call(topic: new_topic)
        end
      rescue Community::SectionHierarchyLock::TopicSectionChanged,
        Community::SectionHierarchyLock::HierarchyChanged,
        ActiveRecord::Deadlocked
        lock_attempts += 1
        fresh_topic = Community::Topic.with_discarded.find_by(id: @topic.id)
        fresh_section = @requested_section && Community::Section.find_by(id: @requested_section.id)
        if lock_attempts <= 2 && fresh_topic && (!@requested_section || fresh_section)
          @topic = fresh_topic
          @section = fresh_section
          retry
        end
        return ServiceResult.failure(error: :topic_not_available)
      end

      Administration::AuditLogger.call(
        actor: @user,
        action: "forum.topic.split",
        resource: new_topic,
        metadata: { source_topic: @topic.public_id, from_floor: @post.floor_number }
      )
      ServiceResult.success(new_topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
