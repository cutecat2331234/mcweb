# frozen_string_literal: true

module Commerce
  module Disputes
    class CustomerOrderProps
      PUBLIC_CUSTOMER_EVENT_TYPES = %w[
        customer_opened customer_withdrawn customer_refund_resolved
      ].freeze
      PUBLIC_EVENT_KINDS = Commerce::Disputes::CustomerNotifier::PUBLIC_EVENT_KINDS

      def initialize(order:, viewer:)
        @order = order
        @viewer = viewer
      end

      def call
        unless CustomerPolicy.order_owned_by?(order: @order, actor: @viewer)
          raise ActiveRecord::RecordNotFound
        end

        payment = @order.primary_succeeded_payment_record
        disputes = @order.disputes
          .includes(events: :actor)
          .recent
          .limit(20)
          .to_a
        refunds = payment ? payment.refunds.to_a : []
        payment_disputes = payment ? payment.disputes.to_a : []
        max_amount_cents = if payment
          CustomerPolicy.available_cents(
            payment:,
            refunds:,
            disputes: payment_disputes
          )
        else
          0
        end

        {
          create: {
            allowed: CustomerPolicy.create_allowed?(
              order: @order,
              payment:,
              refunds:,
              disputes: payment_disputes
            ),
            url: route_helpers.store_order_disputes_path(@order),
            max_amount_cents:,
            max_amount_label: format_money(max_amount_cents, @order.currency),
            description_min_length: CreateCustomerDispute::MIN_DESCRIPTION_LENGTH,
            description_max_length: CreateCustomerDispute::MAX_DESCRIPTION_LENGTH,
            reason_options: CreateCustomerDispute::REASON_KINDS.map do |reason|
              {
                value: reason,
                label: translate("reasons.#{reason}")
              }
            end
          },
          upload_url: route_helpers.secure_evidence_attachments_path,
          evidence_limits: {
            max_files: Commerce::SecureEvidenceSubjects::MAX_ATTACHMENTS,
            max_file_bytes: Commerce::SecureEvidenceSubjects::MAX_FILE_BYTES
          },
          cases: disputes.map { |dispute| serialize_dispute(dispute) }
        }
      end

      private

      def serialize_dispute(dispute)
        attachments = customer_attachments(dispute)
        {
          public_id: dispute.public_id,
          status: dispute.status,
          status_label: translate("statuses.#{dispute.status}"),
          amount_label: format_money(dispute.amount_cents, dispute.currency),
          rights_status: dispute.rights_status,
          rights_status_label: translate("rights_statuses.#{dispute.rights_status}"),
          evidence_due_at: localized_time(dispute.evidence_due_at),
          created_at: localized_time(dispute.customer_opened_at || dispute.created_at),
          updated_at: localized_time(dispute.updated_at),
          can_upload_evidence: CustomerPolicy.evidence_allowed?(
            dispute:,
            actor: @viewer
          ),
          can_withdraw: dispute.customer_withdrawable_by?(@viewer),
          withdraw_url: dispute.customer_withdrawable_by?(@viewer) ?
            route_helpers.store_order_dispute_path(@order, dispute) :
            nil,
          evidence_subject: {
            key: Commerce::SecureEvidenceSubjects::SUBJECT_KEY,
            public_id: dispute.public_id
          },
          attachments: attachments.map { |attachment| serialize_attachment(attachment) },
          timeline: serialize_timeline(dispute, attachments)
        }
      end

      def customer_attachments(dispute)
        SecureEvidence::Attachment
          .includes(:upload_record)
          .where(
            uploader: @viewer,
            subject_key: Commerce::SecureEvidenceSubjects::SUBJECT_KEY,
            subject_id: dispute.id,
            subject_public_id: dispute.public_id
          )
          .order(:created_at, :id)
          .to_a
      end

      def serialize_attachment(attachment)
        downloadable = SecureEvidence::AttachmentAccess.download_allowed?(
          attachment,
          actor: @viewer
        )
        {
          public_id: attachment.public_id,
          filename: attachment.filename,
          byte_size: attachment.byte_size,
          byte_size_label: ActiveSupport::NumberHelper.number_to_human_size(
            attachment.byte_size
          ),
          state: attachment.state,
          scan_status: attachment.scan_status,
          status_label: translate("evidence.statuses.#{attachment_status(attachment)}"),
          created_at: localized_time(attachment.created_at),
          download_url: downloadable ?
            route_helpers.secure_evidence_attachment_path(attachment) :
            nil,
          scan_status_url: route_helpers.scan_status_secure_evidence_attachment_path(
            attachment
          )
        }
      end

      def serialize_timeline(dispute, attachments)
        event_items = dispute.events.timeline.filter_map do |event|
          next unless public_event?(dispute, event)

          {
            key: "event-#{event.id}",
            label: event_label(event),
            description: customer_event_description(dispute, event),
            status: event.to_status,
            occurred_at_value: event.created_at
          }
        end
        attachment_items = attachments.map do |attachment|
          {
            key: "attachment-#{attachment.public_id}",
            label: translate(
              "timeline.evidence_added",
              filename: attachment.filename
            ),
            description: nil,
            status: nil,
            occurred_at_value: attachment.created_at
          }
        end

        (event_items + attachment_items)
          .sort_by { |item| item.fetch(:occurred_at_value) }
          .map do |item|
            item.except(:occurred_at_value).merge(
              occurred_at: localized_time(item.fetch(:occurred_at_value))
            )
          end
      end

      def public_event?(dispute, event)
        if %w[customer_opened customer_withdrawn].include?(event.event_type)
          return event.actor_id == @viewer.id &&
            dispute.customer_opened_by_id == @viewer.id
        end
        return true if event.event_type == "customer_refund_resolved"

        PUBLIC_EVENT_KINDS.include?(event.metadata["customer_event_kind"])
      end

      def customer_event_description(dispute, event)
        return unless %w[customer_opened customer_withdrawn].include?(event.event_type)
        return unless event.actor_id == @viewer.id && dispute.customer_opened_by_id == @viewer.id

        event.note
      end

      def event_label(event)
        return translate("timeline.#{event.event_type}") if PUBLIC_CUSTOMER_EVENT_TYPES.include?(event.event_type)
        event_kind = event.metadata["customer_event_kind"].to_s
        if event_kind == "rights_changed" && rights_status_changed?(event)
          return translate(
            "timeline.rights_changed",
            status: translate(
              "rights_statuses.#{event.metadata['rights_status']}"
            )
          )
        end
        if %w[provider_opened provider_bound].include?(event_kind)
          return translate("timeline.#{event_kind}")
        end

        translate(
          "timeline.status_changed",
          status: translate("statuses.#{event.to_status}")
        )
      end

      def rights_status_changed?(event)
        previous = event.metadata["previous_rights_status"].to_s
        current = event.metadata["rights_status"].to_s
        previous.present? && current.present? && previous != current
      end

      def attachment_status(attachment)
        return attachment.state unless attachment.state_pending?

        attachment.scan_status
      end

      def localized_time(value)
        I18n.l(value, format: :short) if value
      end

      def format_money(cents, currency)
        ApplicationController.helpers.format_currency_from_cents(cents, currency)
      end

      def translate(key, **options)
        I18n.t("mcweb.commerce.payment_disputes.#{key}", **options)
      end

      def route_helpers
        Rails.application.routes.url_helpers
      end
    end
  end
end
