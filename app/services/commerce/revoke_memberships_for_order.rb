# frozen_string_literal: true

module Commerce
  class RevokeMembershipsForOrder < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      revoked = 0
      retry_queued = 0
      error_result = nil

      Commerce::Order.transaction do
        @order.lock!
        item_ids = @order.items.order(:id).pluck(:id)
        memberships = Commerce::UserMembership
          .where(source_order_item_id: item_ids, status: %w[active revoked])
          .includes(:membership_type, :user)
          .order(:user_id, :store_membership_type_id, :id)

        memberships.each do |membership|
          was_active = membership.active?
          result = Commerce::RevokeMembership.call(
            membership: membership,
            idempotency_key: "refund-membership:#{membership.id}:revoke"
          )

          if result.failure?
            error_result = result
            raise ActiveRecord::Rollback
          end

          revoked += 1 if was_active
          retry_queued += result.value.to_h.dig(:command, :retried).to_i
        end
      end

      return error_result if error_result

      ServiceResult.success(revoked: revoked, retry_queued: retry_queued)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
