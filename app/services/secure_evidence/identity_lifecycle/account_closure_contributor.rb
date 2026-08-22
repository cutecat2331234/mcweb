# frozen_string_literal: true

module SecureEvidence
  module IdentityLifecycle
    module AccountClosureContributor
      module_function

      def preflight(context:)
        relation = Attachment.where(uploader: context.user)
        held = DataGovernance::RetentionHold.effective.exists?(target: context.user)
        retained = relation.where.not(state: "purged")
        retained = retained.where("retention_until > ?", context.at) unless held

        ::Identity::AccountClosure::Contribution.ready(
          details: {
            outcome: "evidence_metadata_retained",
            total_records: relation.count,
            retained_files: retained.count,
            expired_files: held ? 0 : relation.where.not(state: "purged")
              .where(retention_until: ..context.at).count,
            account_retention_hold: held
          }
        )
      end

      def execute(context:, preflight:)
        ::Identity::AccountClosure::Contribution.completed(
          details: preflight.details.merge(
            "uploader_identity" => "stable_public_id_snapshot",
            "file_cleanup" => "retention_scheduler_owned"
          )
        )
      rescue StandardError => error
        ::Identity::AccountClosure::Contribution.failed(
          code: "secure_evidence_account_closure_failed",
          details: { failure_class: error.class.name }
        )
      end

      def compensate(context:, execution:)
        ::Identity::AccountClosure::Contribution.compensated(
          details: {
            outcome: "no_mutation_required",
            at: context.at.iso8601,
            prior_status: execution.status
          }
        )
      end
    end
  end
end
