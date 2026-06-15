module Commerce
  class Order < ApplicationRecord
    include HasPublicId
    include AASM

    STATUSES = %w[
      pending awaiting_payment paid processing fulfilling
      fulfilled completed cancelled refunded failed
    ].freeze

    belongs_to :user
    belongs_to :coupon, class_name: "Commerce::Coupon", foreign_key: :store_coupon_id, optional: true
    belongs_to :gift_card, class_name: "Commerce::GiftCard", foreign_key: :store_gift_card_id, optional: true
    has_many :items, class_name: "Commerce::OrderItem", foreign_key: :store_order_id, dependent: :destroy
    has_many :events, class_name: "Commerce::OrderEvent", foreign_key: :store_order_id, dependent: :destroy
    has_many :fulfillments, class_name: "Commerce::Fulfillment", foreign_key: :store_order_id, dependent: :destroy
    has_many :refunds, class_name: "Commerce::Refund", foreign_key: :store_order_id, dependent: :destroy
    has_many :payment_records, class_name: "Payments::Record", foreign_key: :store_order_id, dependent: :destroy
    has_many :staff_notes, class_name: "Commerce::OrderStaffNote", foreign_key: :store_order_id, dependent: :destroy

    validates :order_number, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :subtotal_cents, :discount_cents, :total_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :currency, presence: true

    before_validation :generate_order_number, on: :create

    aasm column: :status, whiny_transitions: false do
      state :pending, initial: true
      state :awaiting_payment, :paid, :processing, :fulfilling, :fulfilled, :completed, :cancelled, :refunded, :failed

      event :submit_payment do
        transitions from: :pending, to: :awaiting_payment
      end

      event :mark_paid do
        transitions from: :awaiting_payment, to: :paid
      end

      event :start_processing do
        transitions from: :paid, to: :processing
      end

      event :start_fulfilling do
        transitions from: :processing, to: :fulfilling
      end

      event :mark_fulfilled do
        transitions from: %i[paid processing fulfilling], to: :fulfilled
      end

      event :complete do
        transitions from: :fulfilled, to: :completed
      end

      event :cancel do
        transitions from: %i[pending awaiting_payment], to: :cancelled
      end

      event :fail do
        transitions from: %i[awaiting_payment processing fulfilling], to: :failed
      end

      event :refund do
        transitions from: %i[paid processing fulfilling fulfilled completed], to: :refunded
      end

      after_all_transitions :record_transition_event
    end

    scope :recent, -> { order(created_at: :desc) }

    def total
      total_cents / 100.0
    end

    def may_transition_to?(target_status)
      aasm.states(permitted: true).map(&:name).include?(target_status.to_sym)
    end

    private

    def generate_order_number
      self.order_number ||= "ORD-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
    end

    def record_transition_event
      events.create!(
        event_type: aasm.current_event.to_s.sub(/!$/, ""),
        from_status: aasm.from_state.to_s,
        to_status: aasm.to_state.to_s
      )
    end
  end
end
