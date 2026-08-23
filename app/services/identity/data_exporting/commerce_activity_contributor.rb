# frozen_string_literal: true

module Identity
  module DataExporting
    class CommerceActivityContributor
      WISHLIST_FIELDS = %w[id store_product_id variant_id note created_at updated_at].freeze
      WISHLIST_PRESET_FIELDS = %w[id name filters created_at updated_at].freeze
      ALERT_FIELDS = %w[id store_product_id notified_at created_at updated_at].freeze
      REVIEW_FIELDS = %w[
        id store_product_id forum_post_id rating body status merchant_reply merchant_replied_at
        deleted_at created_at updated_at
      ].freeze
      HELPFUL_VOTE_FIELDS = %w[id store_review_id created_at updated_at].freeze
      QUESTION_FIELDS = %w[
        id store_product_id store_order_item_id body status edited_at deleted_at created_at updated_at
      ].freeze
      PAYMENT_FIELDS = %w[
        id store_order_id provider provider_mode provider_payment_id status amount_cents currency
        created_at updated_at
      ].freeze
      PAYMENT_ATTEMPT_FIELDS = %w[id payment_record_id status created_at updated_at].freeze
      REFUND_FIELDS = %w[
        id store_order_id payment_record_id amount_cents status reason reason_kind
        requested_by_customer restoration_status provider_confirmed_at withdrawn_at
        created_at updated_at
      ].freeze
      DISPUTE_FIELDS = %w[
        id public_id store_order_id payment_record_id kind status amount_cents currency
        reason_code resolution rights_status evidence_due_at customer_opened_at
        customer_withdrawn_at closed_at created_at updated_at
      ].freeze
      DISPUTE_EVENT_FIELDS = %w[
        id store_dispute_id source event_type from_status to_status provider_status
        provider_occurred_at created_at
      ].freeze

      def self.call(context:)
        user = context.user
        order_ids = Commerce::Order.where(user:).select(:id)
        payments = Payments::Record.where(store_order_id: order_ids)
        disputes = Commerce::Dispute.where(store_order_id: order_ids)

        Contribution.new(
          documents: {
            "commerce/wishlist/items.json" => RecordSerializer.records(
              Commerce::WishlistItem.where(user:).order(:id),
              WISHLIST_FIELDS
            ),
            "commerce/wishlist/presets.json" => RecordSerializer.records(
              Commerce::WishlistFilterPreset.where(user:).order(:id),
              WISHLIST_PRESET_FIELDS
            ),
            "commerce/availability-alerts.json" => RecordSerializer.records(
              Commerce::ProductAvailabilityAlert.where(user:).order(:id),
              ALERT_FIELDS
            ),
            "commerce/reviews.json" => RecordSerializer.records(
              Commerce::Review.where(user:).order(:id),
              REVIEW_FIELDS
            ),
            "commerce/review-helpful-votes.json" => RecordSerializer.records(
              Commerce::ReviewHelpfulVote.where(user:).order(:id),
              HELPFUL_VOTE_FIELDS
            ),
            "commerce/product-questions.json" => RecordSerializer.records(
              Commerce::ProductQuestion.where(user:).order(:id),
              QUESTION_FIELDS
            ),
            "commerce/payments.json" => RecordSerializer.records(
              payments.order(:id),
              PAYMENT_FIELDS
            ),
            "commerce/payment-attempts.json" => RecordSerializer.records(
              Payments::Attempt.where(payment_record_id: payments.select(:id)).order(:id),
              PAYMENT_ATTEMPT_FIELDS
            ),
            "commerce/refunds.json" => RecordSerializer.records(
              Commerce::Refund.where(store_order_id: order_ids).order(:id),
              REFUND_FIELDS
            ),
            "commerce/disputes.json" => RecordSerializer.records(
              disputes.order(:id),
              DISPUTE_FIELDS
            ),
            "commerce/dispute-events.json" => RecordSerializer.records(
              Commerce::DisputeEvent.where(store_dispute_id: disputes.select(:id)).order(:id),
              DISPUTE_EVENT_FIELDS
            )
          }
        )
      end
    end
  end
end
