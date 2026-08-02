# frozen_string_literal: true

module Community
  class SectionLifecycleImpact
    def self.call(section:)
      new(section: section).call
    end

    def initialize(section:)
      @section = section
    end

    def call
      section_ids = subtree_ids
      topic_scope = Community::Topic.where(forum_section_id: section_ids)
      moderation_scope = Community::ModerationCase.where(forum_section_id: section_ids)

      {
        sections: section_ids.length,
        descendants: section_ids.length - 1,
        topics: topic_scope.count,
        posts: Community::Post.where(forum_topic_id: topic_scope.select(:id)).count,
        moderation_cases: moderation_scope.count,
        active_moderation_cases: moderation_scope.active_queue.count,
        moderators: Community::SectionModerator.where(forum_section_id: section_ids).count,
        subscriptions: Community::Subscription.where(
          subscribable_type: "Community::Section",
          subscribable_id: section_ids
        ).count,
        member_mutes: Community::SectionMute.where(forum_section_id: section_ids).count,
        moderation_mutes: Community::Mute.where(forum_section_id: section_ids).count
      }
    end

    private

    def subtree_ids
      found = []
      pending = [ @section.id ]

      while pending.any?
        batch = pending - found
        break if batch.empty?

        found.concat(batch)
        pending = Community::Section.where(parent_id: batch).pluck(:id)
      end

      found
    end
  end
end
