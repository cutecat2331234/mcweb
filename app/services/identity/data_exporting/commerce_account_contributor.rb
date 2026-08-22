# frozen_string_literal: true

module Identity
  module DataExporting
    class CommerceAccountContributor
      ORDER_FIELDS = %w[
        public_id order_number status currency subtotal_cents discount_cents total_cents
        store_credit_amount_cents created_at updated_at
      ].freeze
      MEMBERSHIP_FIELDS = %w[id store_membership_type_id status source starts_at expires_at created_at].freeze
      ENTITLEMENT_FIELDS = %w[id store_product_id starts_at expires_at revoked_at created_at].freeze

      def self.call(context:)
        user = context.user
        Contribution.new(
          documents: {
            "commerce/orders.json" => RecordSerializer.records(
              Commerce::Order.where(user:).order(:id),
              ORDER_FIELDS
            ),
            "commerce/memberships.json" => RecordSerializer.records(
              Commerce::UserMembership.where(user:).order(:id),
              MEMBERSHIP_FIELDS
            ),
            "commerce/entitlements.json" => RecordSerializer.records(
              Commerce::UserEntitlement.where(user:).order(:id),
              ENTITLEMENT_FIELDS
            ),
            "commerce/shipping-addresses.json" => shipping_addresses(user)
          }
        )
      end

      def self.shipping_addresses(user)
        Commerce::ShippingAddress.where(user:).order(:id).map do |address|
          address.to_address_hash.merge(
            "id" => address.id,
            "label" => address.label,
            "default" => address.default_address?,
            "created_at" => address.created_at
          )
        end
      end
      private_class_method :shipping_addresses
    end
  end
end
