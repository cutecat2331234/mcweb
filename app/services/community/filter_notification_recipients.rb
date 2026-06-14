# frozen_string_literal: true

module Community
  class FilterNotificationRecipients < ApplicationService
    def initialize(actor_id:, recipient_ids:)
      @actor_id = actor_id
      @recipient_ids = Array(recipient_ids).map(&:to_i).uniq
    end

    def call
      return ServiceResult.success([]) if @recipient_ids.empty?

      ignored = Community::UserIgnore.where(ignored_id: @actor_id, ignorer_id: @recipient_ids).pluck(:ignorer_id)
      blocking = Community::UserBlock.where(blocked_id: @actor_id, blocker_id: @recipient_ids).pluck(:blocker_id)
      blocked = Community::UserBlock.where(blocker_id: @actor_id, blocked_id: @recipient_ids).pluck(:blocked_id)

      ServiceResult.success(@recipient_ids - ignored - blocking - blocked)
    end
  end
end
