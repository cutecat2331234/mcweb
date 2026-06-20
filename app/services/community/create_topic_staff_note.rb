# frozen_string_literal: true

module Community
  class CreateTopicStaffNote < ApplicationService
    def initialize(actor:, topic:, body:)
      @actor = actor
      @topic = topic
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "staff_note_unauthorized") unless @actor.permission?("forum.topics.lock") || @actor.permission?("admin.access")
      return ServiceResult.failure(error: "staff_note_blank") if @body.blank?

      note = Community::TopicStaffNote.create!(
        topic: @topic,
        author: @actor,
        body: @body
      )

      ServiceResult.success(note)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
