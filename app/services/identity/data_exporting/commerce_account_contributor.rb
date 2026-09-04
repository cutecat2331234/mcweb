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
      STORE_CREDIT_TRANSACTION_FIELDS = %w[
        id amount_cents note balance_before_cents balance_after_cents created_at updated_at
      ].freeze

      def self.call(context:)
        user = context.user
        Contribution.new(
          documents: {
            "commerce/orders.json" => RecordSerializer.stream_records(
              Commerce::Order.where(user:).order(:id),
              ORDER_FIELDS
            ),
            "commerce/memberships.json" => RecordSerializer.stream_records(
              Commerce::UserMembership.where(user:).order(:id),
              MEMBERSHIP_FIELDS
            ),
            "commerce/entitlements.json" => RecordSerializer.stream_records(
              Commerce::UserEntitlement.where(user:).order(:id),
              ENTITLEMENT_FIELDS
            ),
            "commerce/store-credit-transactions.json" => store_credit_transactions(user),
            "commerce/shipping-addresses.json" => shipping_addresses(user)
          }
        )
      end

      def self.shipping_addresses(user)
        RecordSerializer.stream_relation(Commerce::ShippingAddress.where(user:).order(:id)) do |address|
          address.to_address_hash.merge(
            "id" => address.id,
            "label" => address.label,
            "default" => address.default_address?,
            "created_at" => address.created_at
          )
        end
      end
      private_class_method :shipping_addresses

      def self.store_credit_transactions(user)
        scope = Commerce::StoreCreditTransaction.where(user:).includes(:order)
        StreamingDocument.new(declared_count: scope.count, format: :json_array) do
          Enumerator.new do |records|
            scope.reorder(nil).find_in_batches(
              batch_size: RecordSerializer::DEFAULT_STREAM_BATCH_SIZE,
              order: :asc
            ) do |batch|
              batch.each do |transaction|
                records << RecordSerializer.record(transaction, STORE_CREDIT_TRANSACTION_FIELDS).merge(
                  "source" => store_credit_source(transaction),
                  "order_public_id" => transaction.order&.public_id,
                  "order_number" => transaction.order&.order_number
                )
              end
            end
          end
        end
      end
      private_class_method :store_credit_transactions

      def self.store_credit_source(transaction)
        if transaction.order
          transaction.amount_cents.positive? ? "order_refund" : "order_debit"
        elsif transaction.request_id.present?
          "staff_adjustment"
        elsif transaction.amount_cents.positive?
          "credit"
        else
          "debit"
        end
      end
      private_class_method :store_credit_source
    end
  end
end
