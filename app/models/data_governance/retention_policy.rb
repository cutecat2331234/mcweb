# frozen_string_literal: true

module DataGovernance
  class RetentionPolicy < ApplicationRecord
    self.table_name = "data_retention_policies"

    validates :resource_type, presence: true, uniqueness: true
    validates :retention_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

    DEFAULTS = [
      { resource_type: "Community::Topic", retention_days: 30, user_deletable: true, moderator_restorable: true },
      { resource_type: "Community::Post", retention_days: 30, user_deletable: true, moderator_restorable: true },
      { resource_type: "Community::Message", retention_days: 30, user_deletable: true, moderator_restorable: true },
      { resource_type: "Community::PostAttachment", retention_days: 30, user_deletable: true, moderator_restorable: true },
      { resource_type: "Community::ProfilePost", retention_days: 30, user_deletable: true, moderator_restorable: true },
      { resource_type: "Community::ProfilePostComment", retention_days: 30, user_deletable: true, moderator_restorable: true },
      { resource_type: "Notification", retention_days: 365, user_deletable: true, moderator_restorable: false },
      { resource_type: "Community::Report", retention_days: nil, user_deletable: false, moderator_restorable: false },
      { resource_type: "AuditLog", retention_days: nil, user_deletable: false, moderator_restorable: false }
    ].freeze

    def self.ensure_defaults!
      DEFAULTS.each do |attributes|
        find_or_create_by!(resource_type: attributes.fetch(:resource_type)) do |policy|
          policy.assign_attributes(attributes)
        end
      end
    end
  end
end
