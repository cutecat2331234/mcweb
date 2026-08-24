# frozen_string_literal: true

class RepairForumReportOutcomeDeliveryContract < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION public.forum_report_outcome_deliveries_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        report_status text;
        report_outcome text;
        report_owner_id bigint;
        report_reference text;
        notification_owner_id bigint;
        notification_kind text;
        notification_metadata jsonb;
      BEGIN
        SELECT reports.status,
               reports.public_outcome_code,
               reports.reporter_id,
               reports.public_id,
               notifications.user_id,
               notifications.notification_type,
               notifications.metadata
        INTO report_status,
             report_outcome,
             report_owner_id,
             report_reference,
             notification_owner_id,
             notification_kind,
             notification_metadata
        FROM forum_reports reports
        INNER JOIN notifications ON notifications.id = NEW.notification_id
        WHERE reports.id = NEW.forum_report_id
        FOR UPDATE OF reports;

        IF NEW.notification_id IS NULL
           OR report_status IS NULL
           OR report_status NOT IN ('reviewed', 'dismissed', 'actioned')
           OR report_outcome IS NULL
           OR NEW.public_outcome_code IS DISTINCT FROM report_outcome
           OR notification_owner_id IS DISTINCT FROM report_owner_id
           OR notification_kind IS DISTINCT FROM 'forum.report_outcome'
           OR notification_metadata ->> 'report_public_id' IS DISTINCT FROM report_reference
           OR notification_metadata ->> 'public_outcome_code' IS DISTINCT FROM NEW.public_outcome_code
           OR notification_metadata ->> 'path' IS DISTINCT FROM '/app/forum/reports/' || report_reference THEN
          RAISE EXCEPTION 'forum report outcome delivery contract is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "The repaired report outcome delivery guard must not be restored to an invalid definition"
  end
end
