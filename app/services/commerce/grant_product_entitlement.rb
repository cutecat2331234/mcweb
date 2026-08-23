# frozen_string_literal: true

module Commerce
  class GrantProductEntitlement < ApplicationService
    def initialize(order_item:)
      @order_item = order_item
      @order = order_item.order
    end

    def call
      snapshot = @order_item.fulfillment_snapshot || {}
      product_type = snapshot["product_type"] || snapshot[:product_type]
      return ServiceResult.success(skipped: true) if product_type == "membership"

      config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
      config = config.with_indifferent_access

      return ServiceResult.success(skipped: true) unless entitlement_configured?(config)

      starts_at = Time.current
      expires_at = if config[:entitlement_permanent]
                     nil
      elsif config[:entitlement_days].to_i.positive?
                     config[:entitlement_days].to_i.days.from_now
      else
                     return ServiceResult.success(skipped: true)
      end

      result = nil
      Commerce::UserEntitlement.transaction do
        entitlement = Commerce::UserEntitlement.find_by(
          source_order_item_id: @order_item.id
        )
        entitlement ||= Commerce::UserEntitlement.create!(
          user: @order.user,
          store_product_id: @order_item.store_product_id,
          source_order_item: @order_item,
          starts_at: starts_at,
          expires_at: expires_at
        )

        protection = protect_dispute_rights(entitlement)
        unless protection.success?
          result = protection
          raise ActiveRecord::Rollback
        end

        result = ServiceResult.success(entitlement)
      end

      result
    rescue ActiveRecord::RecordNotUnique
      existing = Commerce::UserEntitlement.find_by(source_order_item_id: @order_item.id)
      if existing
        protection = protect_dispute_rights(existing)
        return protection if protection.failure?

        return ServiceResult.success(existing)
      end

      raise
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def entitlement_configured?(config)
      config[:entitlement_permanent] == true || config[:entitlement_days].to_i.positive?
    end

    def protect_dispute_rights(entitlement)
      Commerce::Disputes::ProtectGrantedSubject.call(
        order: @order,
        subject: entitlement
      )
    end
  end
end
