# frozen_string_literal: true

module Community
  class ReportSubjectActionDelivery < ApplicationRecord
    self.table_name = "forum_report_subject_action_deliveries"

    belongs_to :report,
      class_name: "Community::Report",
      foreign_key: :forum_report_id,
      inverse_of: :subject_action_delivery
    belongs_to :notification, optional: true

    attr_readonly :forum_report_id, :notification_id, :created_at

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
