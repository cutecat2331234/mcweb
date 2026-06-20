# frozen_string_literal: true

module Commerce
  class RevokeMembershipsForOrder < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      revoked = 0

      @order.items.find_each do |item|
        memberships = Commerce::UserMembership.active.where(source_order_item_id: item.id)
        memberships.find_each do |membership|
          result = Commerce::RevokeMembership.call(membership: membership)
          revoked += 1 if result.success?
        end
      end

      ServiceResult.success(revoked: revoked)
    end
  end
end
