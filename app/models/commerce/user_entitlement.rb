# frozen_string_literal: true

module Commerce
  class UserEntitlement < ApplicationRecord
    self.table_name = "store_user_entitlements"

    belongs_to :user
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id
    belongs_to :source_order_item, class_name: "Commerce::OrderItem", optional: true
    belongs_to :risk_hold_dispute,
               class_name: "Commerce::Dispute",
               optional: true

    validates :starts_at, presence: true

    scope :currently_active, -> {
      now = Time.current
      where(revoked_at: nil, risk_held_at: nil)
        .where("expires_at IS NULL OR expires_at > ?", now)
    }

    def permanent?
      expires_at.nil?
    end

    def currently_active?
      revoked_at.nil? &&
        risk_held_at.nil? &&
        (expires_at.nil? || expires_at > Time.current)
    end

    def revoke!
      update!(revoked_at: Time.current) unless revoked_at?
    end
  end
end
