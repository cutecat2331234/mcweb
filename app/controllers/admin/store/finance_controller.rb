# frozen_string_literal: true

module Admin
  module Store
    class FinanceController < BaseController
      PER_PAGE = 40

      before_action -> { require_permission("store.finance.read") }
      before_action -> { require_permission("store.finance.documents.manage") },
        only: :transition_document
      before_action -> { require_permission("store.finance.exports.create") },
        only: %i[create_export revoke_export]
      before_action -> { require_permission("store.finance.exports.download") },
        only: :download_export
      before_action :set_document, only: %i[document transition_document]
      before_action :set_finance_export, only: %i[download_export revoke_export]

      def index
        expire_visible_exports
        query = Commerce::FinanceDocumentQuery.new(filter_params)
        @pagy, documents = pagy(:offset, query.relation, limit: PER_PAGE)

        response.set_header("Cache-Control", "private, no-store")
        render inertia: "Admin/Store/Finance/Index", props: {
          filters: query.filters,
          filterOptions: query.options,
          summary: query.summary,
          documents: documents.map { |document| serialize_document(document) },
          pagination: pagy_props(@pagy).merge(limit: PER_PAGE),
          exports: visible_exports.map { |finance_export| serialize_export(finance_export) },
          permissions: {
            manageDocuments: current_user.permission?("store.finance.documents.manage"),
            createExports: current_user.permission?("store.finance.exports.create"),
            downloadExports: current_user.permission?("store.finance.exports.download")
          },
          retention: Commerce::FinanceRetentionPolicy::RULES,
          paths: {
            index: admin_store_finance_path,
            createExport: admin_store_finance_exports_path
          }
        }
      end

      def document
        response.set_header("Cache-Control", "private, no-store")
        render json: serialize_document(@document, detail: true)
      end

      def transition_document
        result = Commerce::TransitionFinanceDocument.call(
          document: @document,
          actor: current_user,
          action: transition_params[:transition_action],
          reason: transition_params[:reason],
          request_id: transition_params[:request_id],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
        render_service_result(result) do |value|
          {
            document: serialize_document(value.fetch(:document), detail: true),
            replayed: value.fetch(:replayed)
          }
        end
      end

      def create_export
        result = Commerce::RequestFinanceExport.call(
          actor: current_user,
          filters: export_params[:filters] || {},
          idempotency_key: export_params[:idempotency_key],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
        render_service_result(result, status: :accepted) do |value|
          {
            finance_export: serialize_export(value.fetch(:finance_export)),
            replayed: value.fetch(:replayed)
          }
        end
      end

      def revoke_export
        result = Commerce::RevokeFinanceExport.call(
          finance_export: @finance_export,
          actor: current_user,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
        render_service_result(result) do |value|
          {
            finance_export: serialize_export(value.fetch(:finance_export)),
            replayed: value.fetch(:replayed)
          }
        end
      end

      def download_export
        result = Commerce::AuthorizeFinanceExportDownload.call(
          finance_export: @finance_export,
          actor: current_user,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
        unless result.success?
          return render json: { error: service_error_message(result), code: result.code },
            status: result.code == "finance_export_unavailable" ? :gone : service_error_status(result)
        end

        finance_export = result.value.fetch(:finance_export)
        response.headers["Cache-Control"] = "private, no-store"
        send_data(
          finance_export.file.download,
          filename: finance_export.file.filename.to_s,
          type: "text/csv",
          disposition: "attachment"
        )
      end

      private

      def set_document
        @document = Commerce::FinanceDocument.find_by!(public_id: params[:id])
      end

      def set_finance_export
        @finance_export = visible_exports_scope.find_by!(public_id: params[:id])
      end

      def filter_params
        params.permit(*Commerce::FinanceDocumentQuery::FILTER_KEYS).to_h
      end

      def export_params
        params.expect(finance_export: [
          :idempotency_key,
          { filters: Commerce::FinanceDocumentQuery::FILTER_KEYS.map(&:to_sym) }
        ])
      end

      def transition_params
        params.expect(finance_document: %i[transition_action reason request_id])
      end

      def visible_exports_scope
        Commerce::FinanceExport.where(requested_by: current_user)
      end

      def visible_exports
        visible_exports_scope
          .with_attached_file
          .includes(:events)
          .recent_first
          .limit(25)
      end

      def expire_visible_exports
        visible_exports_scope.completed.where("expires_at <= ?", Time.current).find_each do |finance_export|
          Commerce::ExpireFinanceExport.call(finance_export:)
        end
      end

      def serialize_document(document, detail: false)
        snapshot = document.tax_snapshot
        payload = {
          id: document.public_id,
          number: document.document_number,
          version: document.version,
          kind: document.document_kind,
          status: document.status,
          channel: document.channel,
          currency: document.currency,
          net_cents: document.net_amount_cents,
          tax_cents: document.tax_amount_cents,
          gross_cents: document.gross_amount_cents,
          issued_at: document.issued_at.iso8601,
          retention_until: document.retention_until.iso8601,
          order: {
            id: document.order.public_id,
            number: document.order.order_number,
            url: admin_store_order_path(document.order)
          },
          refund_id: document.store_refund_id,
          tax: {
            rate_bps: snapshot.tax_rate_bps,
            code: snapshot.tax_code,
            country: snapshot.jurisdiction_country,
            region: snapshot.jurisdiction_region,
            pricing_mode: snapshot.pricing_mode,
            rounding_mode: snapshot.rounding_mode
          },
          paths: {
            detail: admin_store_finance_document_path(document),
            transition: admin_store_finance_document_transition_path(document)
          }
        }
        return payload unless detail

        payload.merge(
          content: document.content_snapshot,
          supersedes: document.supersedes&.public_id,
          superseded_by: document.superseded_by&.public_id,
          voided_at: document.voided_at&.iso8601,
          superseded_at: document.superseded_at&.iso8601,
          events: document.events.chronological.map do |event|
            {
              type: event.event_type,
              actor: event.actor&.username,
              reason: event.reason,
              created_at: event.created_at.iso8601,
              metadata: event.metadata
            }
          end
        )
      end

      def serialize_export(finance_export)
        {
          id: finance_export.public_id,
          status: finance_export.status,
          progress: finance_export.progress_percent,
          format: finance_export.format,
          filters: finance_export.filters,
          row_count: finance_export.row_count,
          requested_at: finance_export.requested_at.iso8601,
          started_at: finance_export.started_at&.iso8601,
          completed_at: finance_export.completed_at&.iso8601,
          expires_at: finance_export.expires_at&.iso8601,
          error_code: finance_export.error_code,
          downloadable:
            current_user.permission?("store.finance.exports.download") &&
              finance_export.downloadable?,
          paths: {
            download: admin_store_finance_export_download_path(finance_export),
            revoke: admin_store_finance_export_revoke_path(finance_export)
          },
          events: finance_export.events.chronological.map do |event|
            {
              status: event.status,
              progress: event.progress_percent,
              created_at: event.created_at.iso8601
            }
          end
        }
      end

      def render_service_result(result, status: :ok)
        response.set_header("Cache-Control", "private, no-store")
        if result.success?
          render json: yield(result.value), status:
        else
          render json: { error: service_error_message(result), code: result.code },
            status: service_error_status(result)
        end
      end
    end
  end
end
