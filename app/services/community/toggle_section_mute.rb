# frozen_string_literal: true

module Community
  class ToggleSectionMute < ApplicationService
    def initialize(user:, section:)
      @user = user
      @section = section
    end

    def call
      lock_attempts = 0
      begin
        Community::Section.transaction do
          @section = Community::SectionHierarchyLock.lock!(@section).sole
          unless Community::SectionAccess.view?(section: @section, user: @user)
            return ServiceResult.failure(error: :section_not_available)
          end

          mute = Community::SectionMute.find_by(user: @user, section: @section)
          if mute
            mute.destroy!
            ServiceResult.success(muted: false)
          else
            Community::SectionMute.create!(user: @user, section: @section)
            ServiceResult.success(muted: true)
          end
        end
      rescue Community::SectionHierarchyLock::HierarchyChanged, ActiveRecord::Deadlocked
        lock_attempts += 1
        fresh_section = Community::Section.find_by(id: @section.id)
        if lock_attempts <= 2 && fresh_section
          @section = fresh_section
          retry
        end
        ServiceResult.failure(error: :section_not_available)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
