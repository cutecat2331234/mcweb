# frozen_string_literal: true

module Commerce
  class DisputeRightsAction < ApplicationRecord
    self.table_name = "store_dispute_rights_actions"

    ACTIONS = %w[freeze revoke restore].freeze
    SUBJECT_TYPES = %w[
      Commerce::UserEntitlement Commerce::UserMembership
    ].freeze

    belongs_to :dispute,
               class_name: "Commerce::Dispute",
               foreign_key: :store_dispute_id
    belongs_to :subject, polymorphic: true
    belongs_to :actor, class_name: "User", optional: true

    validates :action, inclusion: { in: ACTIONS }
    validates :subject_type, inclusion: { in: SUBJECT_TYPES }
    validates :idempotency_key, presence: true, uniqueness: true

    def readonly?
      persisted?
    end
  end
end
