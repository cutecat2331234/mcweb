# frozen_string_literal: true

module Community
  class MoveTopic < ApplicationService
    def initialize(user:, topic:, section:, leave_redirect: false)
      @user = user
      @topic = topic
      @section = section
      @leave_redirect = leave_redirect
    end

    def call(leave_redirect: @leave_redirect)
      unless Community::SectionModeration.can_move_topic?(user: @user, topic: @topic, to_section: @section)
        return ServiceResult.failure(error: "You are not authorized to move this topic.")
      end

      return ServiceResult.failure(error: "Topic is already in this section.") if @topic.forum_section_id == @section.id

      from_section = @topic.section
      ActiveRecord::Base.transaction do
        @topic.update!(section: @section)
        create_redirect_stub(from_section) if leave_redirect
      end
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
        metadata: { from_section: from_section.slug, to_section: @section.slug, left_redirect: leave_redirect }
      )
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    # XenForo-style redirect stub: a lightweight published topic left behind in the
    # FROM section that points readers at the moved thread. It carries one opening
    # post so list/show rendering (which expects a floor-1 post) stays valid.
    def create_redirect_stub(from_section)
      stub = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: from_section,
        user: @topic.user,
        title: "[Moved] #{@topic.title}",
        status: "published",
        redirect_to_topic_id: @topic.id,
        last_posted_at: Time.current,
        last_post_user: @user,
        replies_count: 0
      )
      Community::Post.create!(
        topic: stub,
        user: @topic.user,
        floor_number: 1,
        body: "This thread has been moved.",
        status: "published"
      )
      stub
    end
  end
end
