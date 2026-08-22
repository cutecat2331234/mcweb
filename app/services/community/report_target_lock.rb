# frozen_string_literal: true

module Community
  # Keeps report-target mutations in the same hierarchy -> topic -> post order
  # used by the moderation workbench. Callers must already be in a transaction.
  module ReportTargetLock
    class PostTopicChanged < StandardError; end

    module_function

    def hideable?(reportable)
      [
        Community::Topic,
        Community::Post,
        Community::ProfilePost
      ].any? { |type| reportable.is_a?(type) }
    end

    def lock!(reportable)
      return unless reportable&.persisted?

      case reportable
      when Community::Post
        lock_post!(reportable)
      when Community::Topic
        Community::SectionHierarchyLock.lock_topics!(reportable).first
      else
        reportable.lock!
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def lock_post!(post)
      expected_topic_id = post.forum_topic_id
      topic = Community::Topic.with_discarded.find(expected_topic_id)

      locked_topic = Community::SectionHierarchyLock.lock_topics!(topic).first
      locked_post = Community::Post.with_discarded.where(id: post.id).lock.first
      raise ActiveRecord::RecordNotFound unless locked_post
      raise PostTopicChanged unless locked_post.forum_topic_id == expected_topic_id

      locked_post.association(:topic).target = locked_topic
      locked_post
    end
    private_class_method :lock_post!
  end
end
