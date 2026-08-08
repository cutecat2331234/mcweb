# frozen_string_literal: true

module Staff
  class ModerationCasesController < BaseController
    before_action :set_moderation_case, only: %i[show claim assign notes]

    def index
      sync_result = Community::ModerationWorkbench::SyncCases.call
      query = Community::ModerationWorkbench::Queue.new(
        actor: current_user,
        filters: filter_params
      )
      @pagy, records = pagy(:offset, query.relation, limit: 30)

      render inertia: "Staff/ModerationCases/Index", props: {
        cases: records.map { |moderation_case| query.serialize(moderation_case) },
        pagination: pagy_props(@pagy),
        filters: query.filters,
        filter_options: query.filter_options,
        capabilities: {
          can_assign: true,
          can_note: true,
          can_execute: true
        },
        endpoints: {
          index: staff_moderation_cases_path,
          authorize_action: authorize_action_staff_moderation_cases_path,
          execute_action: execute_action_staff_moderation_cases_path
        },
        sync_warning: sync_result.failure? ? sync_result.error : nil
      }
    end

    def show
      detail = case_detail(@moderation_case)
      return render_service_error(detail) if detail.failure?

      render json: { case: detail.value }
    end

    def claim
      manage_case("claim")
    end

    def assign
      manage_case("assign", assignee_id: params[:assignee_id])
    end

    def notes
      manage_case("note", body: params[:body])
    end

    def authorize_action
      cases = selected_visible_cases
      return render_selection_error unless cases

      result = Community::ModerationWorkbench::ActionAuthorization.issue(
        actor: current_user,
        action: requested_moderation_action,
        moderation_cases: cases,
        attributes: action_attributes,
        request_id: params[:request_id],
        reason: params[:reason]
      )
      return render_service_error(result) if result.failure?

      render json: result.value
    end

    def execute_action
      result = Community::ModerationWorkbench::ExecuteAction.call(
        actor: current_user,
        case_ids: params[:case_ids],
        action: requested_moderation_action,
        attributes: action_attributes,
        request_id: params[:request_id],
        reason: params[:reason],
        authorization_token: params[:authorization_token],
        typed_confirmation: params[:typed_confirmation],
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        surface: "staff"
      )
      if result.failure? && result.value.is_a?(Hash) && result.value[:results].present?
        return render json: result.value.merge(error: result.error, failed: true)
      end
      return render_service_error(result) if result.failure?

      render json: result.value
    end

    private

    def set_moderation_case
      @moderation_case = staff_moderation_policy.visible_scope.find(params[:id])
    end

    def manage_case(action, **attributes)
      result = Community::ModerationWorkbench::ManageCase.call(
        actor: current_user,
        moderation_case: @moderation_case,
        action: action,
        lock_version: params[:lock_version],
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        surface: "staff",
        **attributes
      )
      return render_service_error(result) if result.failure?

      detail = case_detail(result.value.fetch(:moderation_case))
      return render_service_error(detail) if detail.failure?

      render json: { case: detail.value }
    end

    def case_detail(moderation_case)
      Community::ModerationWorkbench::CaseDetail.call(
        actor: current_user,
        moderation_case: moderation_case
      )
    end

    def selected_visible_cases
      ids = Community::ModerationWorkbench::ActionAuthorization.normalize_case_ids(
        params[:case_ids]
      )
      return if ids.empty?

      cases = staff_moderation_policy.visible_scope
        .where(id: ids)
        .order(:id)
        .to_a
      cases if cases.size == ids.size
    end

    def render_selection_error
      render json: { error: "moderation_cases_not_found" }, status: :not_found
    end

    def filter_params
      params.permit(
        :source_kind,
        :status,
        :priority,
        :risk_level,
        :section_id,
        :assignee_id,
        :from,
        :to
      )
    end

    def action_attributes
      value = params.fetch(:attributes, ActionController::Parameters.new)
      value = ActionController::Parameters.new(value) unless value.respond_to?(:permit)
      value.permit(
        :section_id,
        :leave_redirect,
        :points,
        :expire_days,
        :duration_days
      )
    end

    def requested_moderation_action
      request.request_parameters["action"].presence ||
        request.request_parameters[:action].presence
    end

    def render_service_error(result)
      payload = { error: result.error, errors: result.errors }
      payload.merge!(result.value) if result.value.is_a?(Hash)
      render json: payload, status: service_status(result.error)
    end

    def service_status(error)
      value = error.to_s
      return :forbidden if value.include?("forbidden") || value.include?("unauthorized")
      return :conflict if value.include?("conflict") ||
        value.include?("reused") ||
        value.include?("replayed") ||
        value.include?("already_claimed")
      return :not_found if value.include?("not_found") || value.include?("stale")

      :unprocessable_entity
    end
  end
end
