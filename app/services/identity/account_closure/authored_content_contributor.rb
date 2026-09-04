# frozen_string_literal: true

module Identity
  module AccountClosure
    module AuthoredContentContributor
      RESOURCE_CONFIG = {
        # A topic is a shared container. Permanently purging it would cascade to
        # replies owned by other people, so account closure only scrubs the
        # closing author's title and never creates a lifecycle record for it.
        "topics" => { model: Community::Topic, strategy: :scrub_title },
        "posts" => { model: Community::Post, strategy: :soft_delete },
        "messages" => { model: Community::Message, strategy: :soft_delete },
        # Profile posts are shared containers for other members' comments.
        "profile_posts" => { model: Community::ProfilePost, strategy: :scrub_body },
        "profile_post_comments" => {
          model: Community::ProfilePostComment,
          strategy: :soft_delete
        }
      }.freeze

      module_function

      def preflight(context:)
        held = DataGovernance::RetentionHold.effective.exists?(target: context.user)
        counts = resource_counts(context.user)
        outcome = if context.closure_mode == "delete_content"
          "authored_content_deletion_planned"
        else
          "stable_anonymous_author"
        end

        Contribution.ready(
          details: {
            outcome:,
            retention_hold: held,
            records: counts,
            upper_bounds: resource_upper_bounds(context.user)
          }
        )
      end

      def execute(context:, preflight:)
        unless context.closure_mode == "delete_content"
          return Contribution.completed(
            details: preflight.details.except("upper_bounds").merge(
              "outcome" => "stable_anonymous_author"
            )
          )
        end

        request_key = SecureRandom.uuid
        zero_counts = RESOURCE_CONFIG.keys.index_with { 0 }
        Contribution.completed(
          details: {
            outcome: "authored_content_deletion_queued",
            closure_mode: "delete_content",
            retention_hold_at_request: preflight.details.fetch("retention_hold"),
            records: preflight.details.fetch("records"),
            deleted_records: zero_counts,
            retained_records: zero_counts,
            processing: {
              schema_version: AuthoredContentDeletion::SCHEMA_VERSION,
              status: "queued",
              request_key:,
              repair_only: false,
              batch_number: 1,
              resource_index: 0,
              cursors: zero_counts,
              upper_bounds: preflight.details.fetch("upper_bounds"),
              deleted_records: zero_counts,
              retained_records: zero_counts,
              missing_records: zero_counts,
              blocker_counts: {},
              requested_at: context.at.iso8601
            }
          }
        )
      end

      def compensate(context:, execution:)
        Contribution.compensated(
          details: {
            outcome: "deletion_plan_cancelled",
            at: context.at.iso8601,
            prior_status: execution.status
          }
        )
      end

      def resource_counts(user)
        RESOURCE_CONFIG.transform_values do |config|
          records_for(config.fetch(:model), user).count
        end
      end

      def resource_upper_bounds(user)
        RESOURCE_CONFIG.transform_values do |config|
          records_for(config.fetch(:model), user).maximum(:id).to_i
        end
      end

      def records_for(model, user)
        model.unscoped.where(user_id: user.id)
      end
    end
  end
end
