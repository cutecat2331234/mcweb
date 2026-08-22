# frozen_string_literal: true

module Identity
  module AccountClosure
    module AuthoredContentContributor
      RESOURCE_CONFIG = {
        "topics" => {
          model: Community::Topic,
          fields: %w[title status deleted_at updated_at]
        },
        "posts" => {
          model: Community::Post,
          fields: %w[body status deleted_at updated_at]
        },
        "messages" => {
          model: Community::Message,
          fields: %w[body deleted_at updated_at]
        }
      }.freeze

      module_function

      def preflight(context:)
        held = DataGovernance::RetentionHold.effective.exists?(target: context.user)
        counts = resource_counts(context.user)
        outcome = if held
          "legally_retained"
        elsif context.closure_mode == "delete_content"
          "authored_content_deletion_planned"
        else
          "stable_anonymous_author"
        end

        Contribution.ready(
          details: {
            outcome:,
            retention_hold: held,
            records: counts
          }
        )
      end

      def execute(context:, preflight:)
        if preflight.details.fetch("retention_hold")
          return Contribution.completed(
            details: preflight.details.merge("outcome" => "legally_retained")
          )
        end
        unless context.closure_mode == "delete_content"
          return Contribution.completed(
            details: preflight.details.merge("outcome" => "stable_anonymous_author")
          )
        end

        snapshots = {}
        deleted_counts = {}
        blocked_counts = {}
        RESOURCE_CONFIG.each do |key, config|
          snapshots[key] = []
          deleted_counts[key] = 0
          blocked_counts[key] = 0
          records_for(config.fetch(:model), context.user).order(:id).lock.each do |record|
            if deletion_allowed?(record)
              snapshots[key] << snapshot(record, config.fetch(:fields))
              delete_record!(record, key:, at: context.at, locale: context.user.locale)
              deleted_counts[key] += 1
            else
              blocked_counts[key] += 1
            end
          end
        end

        outcome = blocked_counts.values.sum.positive? ?
          "legally_retained" : "authored_content_deleted"
        Contribution.completed(
          details: {
            outcome:,
            deleted_records: deleted_counts,
            retained_records: blocked_counts
          },
          compensation_data: snapshots
        )
      end

      def compensate(context:, execution:)
        snapshots = (execution.compensation_data || {}).to_h
        restored_counts = {}
        RESOURCE_CONFIG.each do |key, config|
          restored_counts[key] = 0
          Array(snapshots[key]).reverse_each do |entry|
            attributes = entry.fetch("attributes")
            config.fetch(:model).unscoped.where(id: entry.fetch("id")).update_all(attributes)
            restored_counts[key] += 1
          end
        end
        Contribution.compensated(details: { restored_records: restored_counts })
      end

      def resource_counts(user)
        RESOURCE_CONFIG.transform_values do |config|
          records_for(config.fetch(:model), user).count
        end
      end
      private_class_method :resource_counts

      def records_for(model, user)
        model.where(user:)
      end
      private_class_method :records_for

      def deletion_allowed?(record)
        result = DataGovernance::DeletionPolicy.call(target: record)
        result.success? && result.value.fetch(:allowed)
      end
      private_class_method :deletion_allowed?

      def snapshot(record, fields)
        {
          "id" => record.id,
          "attributes" => record.attributes.slice(*fields)
        }
      end
      private_class_method :snapshot

      def delete_record!(record, key:, at:, locale:)
        case key
        when "topics"
          record.update!(
            title: I18n.t("mcweb.identity.deleted_content_title", locale:),
            status: :deleted,
            deleted_at: at
          )
        when "posts"
          record.update!(
            body: I18n.t("mcweb.identity.deleted_content_body", locale:),
            status: :deleted,
            deleted_at: at
          )
        when "messages"
          record.update!(
            body: I18n.t("mcweb.identity.deleted_content_body", locale:),
            deleted_at: at
          )
        end
      end
      private_class_method :delete_record!
    end
  end
end
