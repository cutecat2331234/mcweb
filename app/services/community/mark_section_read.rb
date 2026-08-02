# frozen_string_literal: true

module Community
  class MarkSectionRead < ApplicationService
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

          @section.topics.where(status: :published).find_each do |topic|
            max_floor = topic.posts.countable.maximum(:floor_number).to_i
            next if max_floor.zero?

            Community::ReadState.mark_read!(@user, topic, floor: max_floor)
          end

          ServiceResult.success
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
    end
  end
end
