# frozen_string_literal: true

module Admin
  module Store
    class PaymentReconciliationsController < BaseController
      PER_PAGE = 40

      before_action -> {
        require_permission(Payments::ReconciliationDiscrepancy::READ_PERMISSION)
      }
      before_action -> {
        require_permission(Payments::ReconciliationDiscrepancy::REVIEW_PERMISSION)
      }, only: :review
      before_action -> {
        require_permission(Payments::RequestManualReconciliation::PERMISSION)
      }, only: %i[trigger manual_authorization]

      def index
        query = Payments::ReconciliationDiscrepanciesQuery.new(
          status: params[:status],
          kind: params[:kind],
          subject_type: params[:subject_type],
          provider: params[:provider],
          mode: params[:mode],
          query: params[:q]
        )
        @pagy, discrepancies = pagy(:offset, query.relation, limit: PER_PAGE)

        response.set_header("Cache-Control", "no-store")
        render inertia: "Admin/Store/PaymentReconciliations/Index", props: {
          filters: Payments::ReconciliationSerializer.filters(query.filters),
          filterOptions: Payments::ReconciliationSerializer.filter_options(query.filter_options),
          summary: query.summary,
          runs: Payments::ReconciliationRun.recent.limit(14).map do |run|
            Payments::ReconciliationSerializer.run(run)
          end,
          decisions: Payments::ReviewReconciliationDiscrepancy::DECISIONS,
          rows: discrepancies.map { |discrepancy| serialize_discrepancy(discrepancy) },
          pagination: pagy_props(@pagy),
          reviewEnabled: current_user.permission?(
            Payments::ReconciliationDiscrepancy::REVIEW_PERMISSION
          ),
          manualTrigger: manual_trigger_props
        }
      end

      def trigger
        result = Payments::RequestManualReconciliation.call(
          actor: current_user,
          date: params[:date],
          token: params[:token],
          confirmation: params[:confirmation],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        if result.success?
          key =
            if result.value[:enqueued]
              "mcweb.flash.payment_reconciliation_requested"
            else
              "mcweb.flash.payment_reconciliation_already_active"
            end
          redirect_to admin_store_payment_reconciliations_path, notice: t(key)
        else
          redirect_to admin_store_payment_reconciliations_path,
            alert: result.error
        end
      end

      def manual_authorization
        date = Payments::RequestManualReconciliation.normalize_date(params[:date])
        config = Payments::ProviderConfig.for_provider("stripe")
        bounds = Payments::RequestManualReconciliation.date_bounds
        unless date &&
            bounds.cover?(date) &&
            Payments::RequestManualReconciliation.provider_ready?(config)
          return render json: {
            error: "manual_reconciliation_authorization_unavailable"
          }, status: :unprocessable_entity
        end

        response.set_header("Cache-Control", "no-store")
        render json: {
          token: Payments::ManualReconciliationToken.issue(
            actor: current_user,
            config: config,
            date: date
          ),
          confirmation:
            Payments::RequestManualReconciliation.confirmation_for(date)
        }
      end

      def review
        discrepancy = Payments::ReconciliationDiscrepancy.find_by_public_id!(params[:id])
        result = Payments::ReviewReconciliationDiscrepancy.call(
          discrepancy: discrepancy,
          actor: current_user,
          token: params[:token],
          confirmation: params[:confirmation],
          decision: params[:decision],
          note: params[:note],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        if result.success?
          redirect_to admin_store_payment_reconciliations_path,
            notice: t(
              "mcweb.flash.payment_reconciliation_reviewed",
              default: "Reconciliation review recorded."
            )
        else
          redirect_to admin_store_payment_reconciliations_path, alert: result.error
        end
      end

      private

      def manual_trigger_props
        allowed = current_user.permission?(
          Payments::RequestManualReconciliation::PERMISSION
        )
        config = Payments::ProviderConfig.for_provider("stripe")
        ready = allowed &&
          Payments::RequestManualReconciliation.provider_ready?(config)
        bounds = Payments::RequestManualReconciliation.date_bounds
        default_date = bounds.end

        {
          allowed: allowed,
          ready: ready,
          url: ready ? trigger_admin_store_payment_reconciliations_path : nil,
          authorizationUrl: (
            manual_authorization_admin_store_payment_reconciliations_path if ready
          ),
          token: (
            Payments::ManualReconciliationToken.issue(
              actor: current_user,
              config: config,
              date: default_date
            ) if ready
          ),
          minDate: bounds.begin.iso8601,
          maxDate: bounds.end.iso8601,
          defaultDate: default_date.iso8601,
          confirmation: (
            Payments::RequestManualReconciliation.confirmation_for(default_date) if ready
          )
        }
      end

      def serialize_discrepancy(discrepancy)
        action =
          if discrepancy.open? && current_user.permission?(
            Payments::ReconciliationDiscrepancy::REVIEW_PERMISSION
          )
            {
              url: review_admin_store_payment_reconciliation_path(discrepancy),
              token: Payments::ReconciliationReviewToken.issue(discrepancy)
            }
          end

        Payments::ReconciliationSerializer.discrepancy(discrepancy, action: action)
      end
    end
  end
end
