# frozen_string_literal: true

module Community
  class ToggleSectionSubscription < ApplicationService
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

          existing = Community::Subscription.find_by(user: @user, subscribable: @section)
          if existing.nil?
            level = @section.default_notification_level.presence_in(Community::Subscription::NOTIFICATION_LEVELS) || "watching"
            Community::Subscription.subscribe!(@user, @section, level: level)
            return ServiceResult.success(watching: true, notification_level: level)
          end

          next_level = SubscriptionLevelCycler.next_level(existing.notification_level)
          if next_level
            existing.update!(notification_level: next_level)
            ServiceResult.success(watching: true, notification_level: next_level)
          else
            existing.destroy!
            ServiceResult.success(watching: false, notification_level: nil)
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
