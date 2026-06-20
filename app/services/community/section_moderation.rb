# frozen_string_literal: true

module Community
  module SectionModeration
    GLOBAL_ONLY_TOPIC_ACTIONS = %w[
      global_announcement remove_global_announcement assign unassign
      feature unfeature enable_wiki disable_wiki unlist list
    ].freeze

    module_function

    def global_moderator?(user)
      user&.permission?("forum.topics.lock")
    end

    def section_moderator?(user, section)
      return false unless user && section

      Community::SectionModerator.exists?(forum_section_id: section.id, user_id: user.id)
    end

    def can_moderate?(user:, section:)
      return false unless user && section

      global_moderator?(user) || section_moderator?(user, section)
    end

    def can_moderate_topic?(user:, topic:)
      return false unless user && topic

      can_moderate?(user: user, section: topic.section)
    end

    def can_moderate_topic_action?(user:, topic:, action:)
      return false unless user && topic

      action = action.to_s
      return true if global_moderator?(user) && can_moderate_topic?(user: user, topic: topic)
      return false unless can_moderate_topic?(user: user, topic: topic)
      return false if GLOBAL_ONLY_TOPIC_ACTIONS.include?(action)

      true
    end

    def bulk_moderate_authorized?(user:)
      return false unless user

      global_moderator?(user) || Community::SectionModerator.exists?(user_id: user.id)
    end

    def can_edit_topic?(user:, topic:)
      return false unless user && topic

      return true if user.id == topic.user_id
      return true if user.permission?("forum.topics.edit_others")
      return true if global_moderator?(user)

      section_moderator?(user, topic.section)
    end

    def can_edit_post?(user:, post:)
      return false unless user && post

      return true if user.id == post.user_id
      return true if user.permission?("forum.posts.edit_others")
      return true if global_moderator?(user)

      section_moderator?(user, post.topic.section)
    end

    def can_mark_solved?(user:, topic:)
      return false unless user && topic

      return true if global_moderator?(user)
      return true if user.id == topic.user_id

      section_moderator?(user, topic.section)
    end

    def can_move_topic?(user:, topic:, to_section: nil)
      return false unless user && topic

      return true if user.permission?("forum.topics.move") || global_moderator?(user)
      return false unless section_moderator?(user, topic.section)

      return true if to_section.nil?

      section_moderator?(user, to_section)
    end

    def moderated_sections_for(user)
      return Community::Section.none unless user

      if global_moderator?(user) || user.permission?("forum.topics.move")
        Community::Section.all
      else
        Community::Section.where(id: Community::SectionModerator.where(user_id: user.id).select(:forum_section_id))
      end
    end

    def staff_for_any_section?(user)
      return false unless user

      global_moderator?(user) || Community::SectionModerator.exists?(user_id: user.id)
    end

    def pending_posts_scope_for(user)
      scope = Community::Post.pending_review.includes(:user, :attachments, topic: :section)
      return scope if global_moderator?(user)

      section_ids = Community::SectionModerator.where(user_id: user.id).select(:forum_section_id)
      scope.joins(:topic).where(forum_topics: { forum_section_id: section_ids })
    end

    def moderator_users_for(section)
      User.where(id: Community::SectionModerator.where(forum_section_id: section.id).select(:user_id))
    end

    def staff_users_for_section(section)
      global_ids = User.joins(roles: :permissions)
        .where(permissions: { key: "forum.topics.lock" })
        .distinct
        .pluck(:id)
      section_ids = Community::SectionModerator.where(forum_section_id: section.id).pluck(:user_id)
      User.where(id: (global_ids + section_ids).uniq)
    end
  end
end
