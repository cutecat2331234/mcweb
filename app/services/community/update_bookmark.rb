# frozen_string_literal: true

module Community
  class UpdateBookmark < ApplicationService
    def initialize(user:, bookmark:, note: nil, remind_at: nil, label: nil)
      @user = user
      @bookmark = bookmark
      @note = note
      @remind_at = remind_at
      @label = label
    end

    def call
      return ServiceResult.failure(error: "Bookmark not found.") unless @bookmark.user_id == @user.id

      attrs = {}
      attrs[:note] = @note unless @note.nil?
      attrs[:remind_at] = parse_remind_at(@remind_at) unless @remind_at.nil?
      attrs[:label] = @label.to_s.strip.presence unless @label.nil?
      @bookmark.update!(attrs)

      ServiceResult.success(@bookmark)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def parse_remind_at(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    end
  end
end
