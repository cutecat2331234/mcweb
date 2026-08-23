# frozen_string_literal: true

module Commerce
  module Disputes
    module OrderRightsAccess
      DELIVERY_ORDER_STATUSES = %w[
        paid processing fulfilling fulfilled completed
      ].freeze

      module_function

      def restricted?(order)
        return true unless order&.persisted?

        order.disputes
          .where(rights_status: %w[frozen revoked])
          .where("liability_cents > 0")
          .exists?
      end

      def delivery_allowed?(order)
        order&.persisted? &&
          DELIVERY_ORDER_STATUSES.include?(order.status) &&
          !restricted?(order)
      end

      def delivery_allowed_under_lock?(order)
        return false unless order&.persisted?

        order.with_lock do
          delivery_allowed?(order)
        end
      end

      def with_delivery_access(order)
        return false unless order&.persisted?

        order.with_lock do
          if delivery_allowed?(order)
            yield
            true
          else
            false
          end
        end
      end
    end
  end
end
