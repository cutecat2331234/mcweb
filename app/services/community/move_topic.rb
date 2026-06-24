# frozen_string_literal: true

module Community
  class MoveTopic < ApplicationService
    def initialize(user:, topic:, section:)
      @user = user
      @topic = topic
      @section = section
    end

    def call
      unless Community::SectionModeration.can_move_topic?(user: @user, topic: @topic, to_section: @section)
        return ServiceResult.failure(error: "You are not authorized to move this topic.")
      end

      return ServiceResult.failure(error: "Topic is already in this section.") if @topic.forum_section_id == @section.id

      from_section = @topic.section
      @topic.update!(section: @section)
      Community::DispatchForumEventWebhook.call(
        event_type: "topic.moved",
        topic: @topic,
        extra: {
          from_section: {
            slug: from_section.slug,
            name: from_section.name
          },
          to_section: {
            slug: @section.slug,
            name: @section.name
          }
        }
      )
      Administration::AuditLogger.call(
        actor: @user,
        action: "forum.topic.move",
        resource: @topic,
        metadata: { from_section: from_section.slug, to_section: @section.slug }
      )
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
