# frozen_string_literal: true

module Commerce
  class UserMembership < ApplicationRecord
    self.table_name = "store_user_memberships"

    belongs_to :user
    belongs_to :membership_type, class_name: "Commerce::MembershipType", foreign_key: :store_membership_type_id
    belongs_to :source_order_item, class_name: "Commerce::OrderItem", optional: true

    enum :status, { active: "active", expired: "expired", revoked: "revoked" }, validate: true
    enum :source, { purchase: "purchase", admin_grant: "admin_grant", import: "import" }, validate: true, prefix: true

    validates :starts_at, presence: true

    scope :currently_active, -> {
      now = Time.current
      active.where("starts_at <= ?", now).where("expires_at IS NULL OR expires_at > ?", now)
    }

    scope :expired_pending, -> {
      active.where("expires_at IS NOT NULL AND expires_at <= ?", Time.current)
    }

    def permanent?
      expires_at.nil?
    end

    def currently_active?
      active? && (expires_at.nil? || expires_at > Time.current)
    end

    def expire!
      update!(status: :expired) if active?
    end

    def revoke!
      update!(status: :revoked) if active?
    end
  end
end
