# frozen_string_literal: true

module Community
  class ToggleTagSubscription < ApplicationService
    def initialize(user:, tag:)
      @user = user
      @tag = tag
    end

    def call
      existing = Community::Subscription.find_by(user: @user, subscribable: @tag)
      if existing
        existing.destroy!
        ServiceResult.success(watching: false)
      else
        Community::Subscription.subscribe!(@user, @tag)
        ServiceResult.success(watching: true)
      end
    end
  end
end
