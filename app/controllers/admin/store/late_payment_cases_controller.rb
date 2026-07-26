# frozen_string_literal: true

module Admin
  module Store
    class LatePaymentCasesController < BaseController
      PER_PAGE = 40

      before_action -> { require_permission(Payments::LatePaymentCase::PERMISSION) }

      def index
        query = Payments::LatePaymentCasesQuery.new(
          status: params[:status],
          reason: params[:reason],
          provider: params[:provider],
          query: params[:q]
        )
        @pagy, review_cases = pagy(:offset, query.relation, limit: PER_PAGE)

        response.set_header("Cache-Control", "no-store")
        render inertia: "Admin/Store/LatePaymentCases/Index", props: {
          filters: Payments::LatePaymentCaseSerializer.filters(query.filters),
          filterOptions: Payments::LatePaymentCaseSerializer.filter_options(query.filter_options),
          summary: query.summary,
          dispositions: Payments::LatePaymentCase::DISPOSITIONS,
          rows: review_cases.map { |review_case| serialize_case(review_case) },
          pagination: pagy_props(@pagy)
        }
      end

      def acknowledge
        review_case = Payments::LatePaymentCase.find(params[:id])
        result = Payments::AcknowledgeLatePaymentCase.call(
          review_case: review_case,
          actor: current_user,
          token: params[:token],
          confirmation: params[:confirmation],
          disposition: params[:disposition],
          note: params[:note],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        if result.success?
          redirect_to admin_store_late_payment_cases_path,
            notice: t(
              "mcweb.flash.late_payment_acknowledged",
              default: "Late payment review recorded."
            )
        else
          redirect_to admin_store_late_payment_cases_path, alert: result.error
        end
      end

      private

      def serialize_case(review_case)
        action =
          if review_case.open?
            {
              url: acknowledge_admin_store_late_payment_case_path(review_case),
              token: Payments::LatePaymentReviewToken.issue(review_case)
            }
          end

        Payments::LatePaymentCaseSerializer.call(review_case, action: action)
      end
    end
  end
end
