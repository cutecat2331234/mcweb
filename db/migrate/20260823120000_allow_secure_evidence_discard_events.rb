# frozen_string_literal: true

class AllowSecureEvidenceDiscardEvents < ActiveRecord::Migration[8.1]
  CONSTRAINT_NAME = "secure_evidence_events_valid_type"
  EVENT_TYPES = %w[
    created scan_clean scan_infected scan_error downloaded retention_extended
    discarded cleanup_scheduled cleanup_failed purged
  ].freeze

  def up
    remove_check_constraint :secure_evidence_attachment_events,
      name: CONSTRAINT_NAME
    add_check_constraint :secure_evidence_attachment_events,
      "event_type IN (#{EVENT_TYPES.map { |value| connection.quote(value) }.join(', ')})",
      name: CONSTRAINT_NAME
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "discard events are immutable and cannot be removed safely"
  end
end
