# frozen_string_literal: true

module Community
  class ToggleSectionMute < ApplicationService
    def initialize(user:, section:)
      @user = user
      @section = section
    end

    def call
      mute = Community::SectionMute.find_by(user: @user, section: @section)
      if mute
        mute.destroy!
        ServiceResult.success(muted: false)
      else
        Community::SectionMute.create!(user: @user, section: @section)
        ServiceResult.success(muted: true)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
