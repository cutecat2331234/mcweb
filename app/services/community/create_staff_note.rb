# frozen_string_literal: true

module Community
  class CreateStaffNote < ApplicationService
    def initialize(actor:, user:, body:)
      @actor = actor
      @user = user
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "staff_note_unauthorized") unless @actor.permission?("forum.users.warn") || @actor.permission?("admin.access")
      return ServiceResult.failure(error: "staff_note_blank") if @body.blank?

      note = Community::StaffNote.create!(
        user: @user,
        author: @actor,
        body: @body
      )

      ServiceResult.success(note)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
