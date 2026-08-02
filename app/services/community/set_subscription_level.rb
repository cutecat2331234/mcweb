# frozen_string_literal: true

module Community
  class SetSubscriptionLevel < ApplicationService
    def initialize(user:, subscribable:, level:)
      @user = user
      @subscribable = subscribable
      @level = level.to_s
    end

    def call
      return call_for_section if @subscribable.is_a?(Community::Section)

      apply_level
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def call_for_section
      lock_attempts = 0
      begin
        Community::Section.transaction do
          @subscribable = Community::SectionHierarchyLock.lock!(@subscribable).sole
          unless Community::SectionAccess.view?(section: @subscribable, user: @user)
            return ServiceResult.failure(error: :section_not_available)
          end

          apply_level
        end
      rescue Community::SectionHierarchyLock::HierarchyChanged, ActiveRecord::Deadlocked
        lock_attempts += 1
        fresh_section = Community::Section.find_by(id: @subscribable.id)
        if lock_attempts <= 2 && fresh_section
          @subscribable = fresh_section
          retry
        end
        ServiceResult.failure(error: :section_not_available)
      end
    end

    def apply_level
      if @level.blank? || @level == "off"
        Community::Subscription.unsubscribe!(@user, @subscribable)
        return ServiceResult.success(watching: false, notification_level: nil)
      end

      unless Community::Subscription::NOTIFICATION_LEVELS.include?(@level)
        return ServiceResult.failure(error: "invalid_subscription_level")
      end

      Community::Subscription.subscribe!(@user, @subscribable, level: @level)
      ServiceResult.success(watching: true, notification_level: @level)
    end
  end
end
