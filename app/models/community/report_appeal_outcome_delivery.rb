# frozen_string_literal: true

module Community
  class ReportAppealOutcomeDelivery < ApplicationRecord
    self.table_name = "forum_report_appeal_outcome_deliveries"

    belongs_to :appeal,
      class_name: "Community::ReportAppeal",
      foreign_key: :forum_report_appeal_id,
      inverse_of: :outcome_delivery
    belongs_to :notification, optional: true

    validates :public_outcome_code,
      inclusion: { in: %w[upheld overturned] }
    attr_readonly :forum_report_appeal_id,
      :notification_id,
      :public_outcome_code,
      :created_at

    before_update :allow_notification_nullification_only
    before_destroy :prevent_change

    private

    def allow_notification_nullification_only
      allowed = changes_to_save.keys == [ "notification_id" ] &&
        notification_id_change_to_be_saved.first.present? &&
        notification_id_change_to_be_saved.last.nil?
      return if allowed

      prevent_change
    end

    def prevent_change
      errors.add(:base, :immutable)
      throw(:abort)
    end
  end
end
