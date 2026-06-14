# frozen_string_literal: true

module Community
  class ToggleSectionSubscription < ApplicationService
    def initialize(user:, section:)
      @user = user
      @section = section
    end

    def call
      existing = Community::Subscription.find_by(user: @user, subscribable: @section)
      if existing
        existing.destroy!
        ServiceResult.success(watching: false)
      else
        Community::Subscription.subscribe!(@user, @section)
        ServiceResult.success(watching: true)
      end
    end
  end
end
