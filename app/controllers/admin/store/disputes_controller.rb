# frozen_string_literal: true

module Admin
  module Store
    class DisputesController < BaseController
      PER_PAGE = 40

      before_action -> { require_permission("store.disputes.read") }
      before_action :set_dispute,
                    only: %i[
                      show authorize_action execute_action
                      evidence_download_token evidence_download
                    ]
      before_action -> { require_permission("store.disputes.sensitive_read") },
                    only: %i[evidence_download_token evidence_download]

      def index
        scope = filtered_scope
        @pagy, disputes = pagy(:offset, scope, limit: PER_PAGE)

        response.set_header("Cache-Control", "private, no-store")
        render inertia: "Admin/Store/Disputes/Index", props: {
          summary: summary,
          filters: filter_values,
          filterOptions: filter_options,
          rows: disputes.map { |dispute| serialize_row(dispute) },
          pagination: pagy_props(@pagy),
          assignees: assignee_options,
          permissions: permission_props
        }
      end

      def show
        response.set_header("Cache-Control", "private, no-store")
        render json: serialize_detail(@dispute)
      end

      def authorize_action
        result = action_service(authorize_only: true).call
        return render_action_error(result) if result.failure?

        value = result.value
        response.set_header("Cache-Control", "private, no-store")
        render json: {
          authorization_token: value[:authorization_token],
          confirmation: value[:confirmation],
          request_id: value[:request_id],
          expires_in: value[:expires_in],
          preview_items: action_preview_items(value[:preview])
        }
      end

      def execute_action
        result = action_service.call
        return render_action_error(result) if result.failure?

        response.set_header("Cache-Control", "private, no-store")
        render json: {
          request_id: action_params[:request_id],
          idempotent: result.value[:idempotent],
          status: result.value[:dispute].status,
          rights_status: result.value[:dispute].rights_status,
          message: t(
            "mcweb.admin.store.disputes.actions.#{action_params[:action]}.completed"
          )
        }
      end

      def evidence_download_token
        evidence = @dispute.evidence.available.find_by!(public_id: params[:evidence_id])
        result = Commerce::Disputes::EvidenceDownloadToken.issue(
          evidence: evidence,
          actor: current_user
        )
        return render_action_error(result) if result.failure?

        response.set_header("Cache-Control", "private, no-store")
        render json: {
          url: evidence_download_admin_store_dispute_path(
            @dispute,
            evidence_id: evidence.public_id,
            token: result.value[:token]
          ),
          expires_in: result.value[:expires_in]
        }
      end

      def evidence_download
        evidence = @dispute.evidence.find_by!(public_id: params[:evidence_id])
        unless Commerce::Disputes::EvidenceDownloadToken.valid?(
          params[:token],
          evidence: evidence,
          actor: current_user
        )
          return head :gone
        end

        response.set_header("Cache-Control", "private, no-store")
        response.set_header("X-Content-Type-Options", "nosniff")
        send_data(
          evidence.content.to_s,
          filename: evidence.filename,
          type: evidence.content_type,
          disposition: "attachment"
        )
      end

      private

      def set_dispute
        @dispute = Commerce::Dispute.includes(
          :order,
          :payment_record,
          :assigned_to,
          :accepted_loss_by,
          :closed_by
        ).find_by!(public_id: params[:id])
      end

      def filtered_scope
        scope = Commerce::Dispute.includes(:order, :payment_record, :assigned_to).recent
        scope = scope.where(status: params[:status]) if Commerce::Dispute::STATUSES.include?(params[:status])
        scope = scope.where(provider: params[:provider]) if params[:provider].present?
        scope = scope.where(risk_level: params[:risk]) if Commerce::Dispute::RISK_LEVELS.include?(params[:risk])
        scope =
          case params[:assignee]
          when "unassigned" then scope.where(assigned_to_id: nil)
          when /\A\d+\z/ then scope.where(assigned_to_id: params[:assignee])
          else scope
          end
        scope =
          case params[:due]
          when "overdue"
            scope.where(status: %w[open evidence_required])
              .where(evidence_due_at: ..Time.current)
          when "soon"
            scope.where(status: %w[open evidence_required])
              .where(evidence_due_at: Time.current..48.hours.from_now)
          else scope
          end

        return scope unless params[:q].present?

        query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
        scope.joins(:order).where(
          "store_disputes.public_id ILIKE :query OR store_orders.order_number ILIKE :query",
          query: query
        )
      end

      def summary
        {
          total: Commerce::Dispute.count,
          active: Commerce::Dispute.where(
            status: %w[open evidence_required evidence_submitted under_review]
          ).count,
          dueSoon: Commerce::Dispute.due_soon.count,
          overdue: Commerce::Dispute.where(status: %w[open evidence_required])
            .where(evidence_due_at: ..Time.current)
            .count,
          liabilityCents: Commerce::Dispute.active_exposure.sum(:liability_cents)
        }
      end

      def filter_values
        params.permit(:q, :status, :provider, :risk, :assignee, :due).to_h
      end

      def filter_options
        {
          statuses: Commerce::Dispute::STATUSES.map do |status|
            { value: status, label: dispute_status_label(status) }
          end,
          providers: Commerce::Dispute.distinct.order(:provider).pluck(:provider).map do |provider|
            { value: provider, label: provider.upcase }
          end,
          risks: Commerce::Dispute::RISK_LEVELS.map do |risk|
            {
              value: risk,
              label: t("mcweb.admin.store.disputes.risks.#{risk}")
            }
          end
        }
      end

      def assignee_options
        User.includes(:roles)
          .order(:username)
          .limit(500)
          .select(&:can_access_admin?)
          .map { |user| { value: user.id.to_s, label: user.username } }
      end

      def serialize_row(dispute)
        {
          publicId: dispute.public_id,
          status: dispute.status,
          statusLabel: dispute_status_label(dispute.status),
          riskLevel: dispute.risk_level,
          riskLabel: t("mcweb.admin.store.disputes.risks.#{dispute.risk_level}"),
          orderNumber: dispute.order.order_number,
          provider: dispute.provider.upcase,
          amount: format_money(dispute.amount_cents, dispute.currency),
          liability: format_money(dispute.liability_cents, dispute.currency),
          evidenceDueAt: dispute.evidence_due_at&.iso8601,
          overdue: dispute.evidence_overdue?,
          assignee: dispute.assigned_to&.username,
          rightsStatus: dispute.rights_status,
          detailUrl: admin_store_dispute_path(dispute)
        }
      end

      def serialize_detail(dispute)
        sensitive = current_user.permission?("store.disputes.sensitive_read")
        {
          dispute: serialize_row(dispute).merge(
            lockVersion: dispute.lock_version,
            kind: dispute.kind,
            providerStatus: localized_provider_status(dispute.provider_status),
            reason: localized_reason(dispute.reason_code),
            offset: format_money(dispute.offset_cents, dispute.currency),
            resolution: dispute.resolution,
            resolutionLabel: dispute.resolution ?
              t("mcweb.admin.store.disputes.resolutions.#{dispute.resolution}") :
              nil,
            rightsStatusLabel: t(
              "mcweb.admin.store.disputes.rights_statuses.#{dispute.rights_status}"
            ),
            createdAt: dispute.created_at.iso8601,
            closedAt: dispute.closed_at&.iso8601,
            retentionUntil: dispute.retention_until&.iso8601,
            retentionBlockers: dispute.retention_blockers.map do |blocker|
              t("mcweb.admin.store.disputes.retention_blockers.#{blocker}")
            end,
            legalHold: dispute.legal_hold?,
            orderUrl: admin_store_order_path(dispute.order),
            sensitive: sensitive ? {
              providerDisputeId: dispute.provider_dispute_id,
              paymentReference: dispute.sensitive_reference,
              paymentAmount: format_money(
                dispute.payment_record.amount_cents,
                dispute.payment_record.currency
              )
            } : nil
          ),
          events: dispute.events.includes(:actor).timeline.limit(200).map do |event|
            {
              id: event.id,
              type: event.event_type,
              typeLabel: localized_event_type(event.event_type),
              source: event.source,
              sourceLabel: t("mcweb.admin.store.disputes.sources.#{event.source}"),
              fromStatus: event.from_status,
              toStatus: event.to_status,
              toStatusLabel: dispute_status_label(event.to_status),
              actor: event.actor&.username,
              note: event.note,
              stale: event.metadata["stale"] == true,
              createdAt: event.created_at.iso8601
            }
          end,
          evidence: dispute.evidence.includes(:submitted_by).order(submitted_at: :desc).map do |item|
            {
              publicId: item.public_id,
              title: item.title,
              filename: item.filename,
              byteSize: item.byte_size,
              sha256: sensitive ? item.sha256 : nil,
              status: item.submission_status,
              statusLabel: t(
                "mcweb.admin.store.disputes.evidence_statuses.#{item.submission_status}"
              ),
              submittedBy: item.submitted_by.username,
              submittedAt: item.submitted_at.iso8601,
              retentionUntil: item.retention_until&.iso8601,
              purgedAt: item.purged_at&.iso8601,
              downloadTokenUrl: sensitive && !item.purged? ?
                evidence_download_token_admin_store_dispute_path(
                  dispute,
                  evidence_id: item.public_id
                ) :
                nil
            }
          end + (sensitive ? secure_evidence_props(dispute) : []),
          permissions: permission_props,
          paths: {
            authorizeAction: authorize_action_admin_store_dispute_path(dispute),
            executeAction: execute_action_admin_store_dispute_path(dispute)
          }
        }
      end

      def permission_props
        {
          sensitiveRead: current_user.permission?("store.disputes.sensitive_read"),
          assign: current_user.permission?("store.disputes.assign"),
          note: current_user.permission?("store.disputes.note"),
          evidenceSubmit: current_user.permission?("store.disputes.evidence_submit"),
          acceptLoss: current_user.permission?("store.disputes.accept_loss"),
          close: current_user.permission?("store.disputes.close"),
          rightsManage: current_user.permission?("store.disputes.rights_manage")
        }
      end

      def secure_evidence_props(dispute)
        SecureEvidence::Attachment
          .includes(:uploader, :upload_record)
          .where(
            subject_key: Commerce::SecureEvidenceSubjects::SUBJECT_KEY,
            subject_id: dispute.id,
            subject_public_id: dispute.public_id
          )
          .order(created_at: :desc, id: :desc)
          .map do |attachment|
            status = attachment.state_pending? ?
              attachment.scan_status :
              attachment.state
            downloadable = SecureEvidence::AttachmentAccess.download_allowed?(
              attachment,
              actor: current_user
            )
            {
              publicId: attachment.public_id,
              title: t("mcweb.admin.store.disputes.customer_evidence_title"),
              filename: attachment.filename,
              byteSize: attachment.byte_size,
              sha256: attachment.sha256,
              status:,
              statusLabel: t(
                "mcweb.commerce.payment_disputes.evidence.statuses.#{status}",
                default: status.to_s.humanize
              ),
              submittedBy: attachment.uploader.username,
              submittedAt: attachment.created_at.iso8601,
              retentionUntil: attachment.retention_until.iso8601,
              purgedAt: attachment.purged_at&.iso8601,
              downloadTokenUrl: nil,
              downloadUrl: downloadable ?
                secure_evidence_attachment_path(attachment) :
                nil
            }
          end
      end

      def action_params
        params.permit(
          :action,
          :request_id,
          :reason,
          :expected_lock_version,
          :assignee_id,
          :note,
          :authorization_token,
          :confirmation,
          evidence: %i[title filename content_type content]
        )
      end

      def action_service(authorize_only: false)
        Commerce::Disputes::ExecuteAction.new(
          actor: current_user,
          dispute: @dispute,
          action: action_params[:action],
          request_id: action_params[:request_id],
          reason: action_params[:reason],
          expected_lock_version: action_params[:expected_lock_version],
          assignee_id: action_params[:assignee_id],
          note: action_params[:note],
          evidence: action_params[:evidence] || {},
          authorization_token: action_params[:authorization_token],
          confirmation: action_params[:confirmation],
          authorize_only: authorize_only,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end

      def action_preview_items(preview)
        [
          [ "dispute", preview[:dispute_public_id] ],
          [ "order", preview[:order_number] ],
          [ "action", t("mcweb.admin.store.disputes.actions.#{preview[:action]}.label") ],
          [ "current_status", dispute_status_label(preview[:current_status]) ],
          [ "next_status", dispute_status_label(preview[:next_status]) ],
          [ "amount", format_money(preview[:amount_cents], preview[:currency]) ],
          [ "liability", format_money(preview[:liability_cents], preview[:currency]) ],
          [
            "rights",
            t("mcweb.admin.store.disputes.rights_statuses.#{preview[:rights_status]}")
          ]
        ].map do |key, value|
          {
            label: t("mcweb.admin.store.disputes.preview.#{key}"),
            value: value.to_s
          }
        end
      end

      def dispute_status_label(status)
        return t("mcweb.labels.not_available") if status.blank?

        t(
          "mcweb.admin.store.disputes.statuses.#{status}",
          default: t("mcweb.labels.not_available")
        )
      end

      def localized_event_type(event_type)
        t(
          "mcweb.admin.store.disputes.event_types.#{event_type.to_s.tr('.', '_')}",
          default: t("mcweb.admin.store.disputes.event_types.updated")
        )
      end

      def localized_provider_status(provider_status)
        return t("mcweb.labels.not_available") if provider_status.blank?

        t(
          "mcweb.admin.store.disputes.provider_statuses.#{provider_status}",
          default: t("mcweb.labels.not_available")
        )
      end

      def localized_reason(reason)
        return t("mcweb.labels.not_available") if reason.blank?

        t(
          "mcweb.admin.store.disputes.reason_codes.#{reason}",
          default: t("mcweb.admin.store.disputes.reason_codes.other")
        )
      end

      def render_action_error(result)
        response.set_header("Cache-Control", "private, no-store")
        render json: { error: service_error_message(result) },
               status: service_error_status(result)
      end
    end
  end
end
