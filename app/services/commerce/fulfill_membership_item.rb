# frozen_string_literal: true

module Commerce
  class FulfillMembershipItem < ApplicationService
    def initialize(order_item:)
      @order_item = order_item
      @order = order_item.order
    end

    def call
      snapshot = @order_item.fulfillment_snapshot || {}
      product_type = snapshot["product_type"] || snapshot[:product_type]
      return ServiceResult.failure(error: I18n.t("mcweb.services.errors.not_a_membership_product")) unless product_type == "membership"

      membership_type_id = snapshot["membership_type_id"] || snapshot[:membership_type_id]
      membership_type = Commerce::MembershipType.find_by(id: membership_type_id) ||
        @order_item.product&.membership_type

      return ServiceResult.failure(error: I18n.t("mcweb.services.errors.membership_type_not_found")) unless membership_type

      grant_result = Commerce::GrantMembership.call(
        user: @order.user,
        membership_type: membership_type,
        source: "purchase",
        source_order_item: @order_item
      )
      return grant_result if grant_result.failure?

      fulfillment = Commerce::Fulfillment.find_by(order_item: @order_item)
      unless fulfillment
        result = Commerce::CreateFulfillment.call(order_item: @order_item)
        return result if result.failure?

        fulfillment = result.value
      end

      fulfillment.mark_fulfilled! unless fulfillment.fulfilled?
      Commerce::SyncOrderFulfillmentStatus.call(order: @order)

      ServiceResult.success(grant_result.value)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
