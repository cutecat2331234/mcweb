# frozen_string_literal: true

module Api
  module V1
    module Staff
      class ModerationCasesController < BaseController
        before_action -> { require_staff_scope!("staff.moderation.claim") }, only: :claim
        before_action -> { require_staff_scope!("staff.moderation.assign") }, only: :assign
        before_action -> { require_staff_scope!("staff.moderation.note") }, only: :notes
        before_action -> { require_staff_scope!("staff.moderation.execute") },
          only: %i[authorize_action execute_action]
        before_action :set_moderation_case, only: %i[show claim assign notes]

        def index
          sync_result = Community::ModerationWorkbench::SyncCases.call
          query = Community::ModerationWorkbench::Queue.new(
            actor: api_user,
            filters: filter_params
          )
          pagy, records = api_paginate(query.relation)

          render json: {
            data: records.map { |record| query.serialize(record) },
            meta: pagination_meta(pagy).merge(
              filters: query.filters,
              filter_options: query.filter_options,
              sync_warning: sync_result.failure? ? sync_result.error : nil
            ),
            links: {
              self: api_v1_staff_moderation_cases_path,
              root: api_v1_staff_root_path
            }
          }
        end

        def show
          detail = case_detail(@moderation_case)
          return render_workbench_error(detail) if detail.failure?

          render json: { data: detail.value }
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
            actor: api_user,
            action: requested_moderation_action,
            moderation_cases: cases,
            attributes: action_attributes,
            request_id: moderation_request_id,
            reason: params[:reason]
          )
          return render_workbench_error(result) if result.failure?

          response.set_header("Idempotency-Key", moderation_request_id)
          render json: { data: result.value }
        end

        def execute_action
          result = Community::ModerationWorkbench::ExecuteAction.call(
            actor: api_user,
            case_ids: params[:case_ids],
            action: requested_moderation_action,
            attributes: action_attributes,
            request_id: moderation_request_id,
            reason: params[:reason],
            authorization_token: params[:authorization_token],
            typed_confirmation: params[:typed_confirmation],
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            surface: "api_staff"
          )
          if result.failure? && result.value.is_a?(Hash) && result.value[:results].present?
            return render json: {
              error: result.error,
              data: result.value
            }, status: service_status(result.error)
          end
          return render_workbench_error(result) if result.failure?

          response.set_header("Idempotency-Key", moderation_request_id)
          render json: { data: result.value }
        end

        private

        def set_moderation_case
          @moderation_case = staff_moderation_policy.visible_scope.find(params[:id])
        end

        def manage_case(action, **attributes)
          result = Community::ModerationWorkbench::ManageCase.call(
            actor: api_user,
            moderation_case: @moderation_case,
            action: action,
            lock_version: params[:lock_version],
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            surface: "api_staff",
            **attributes
          )
          return render_workbench_error(result) if result.failure?

          detail = case_detail(result.value.fetch(:moderation_case))
          return render_workbench_error(detail) if detail.failure?

          render json: { data: detail.value }
        end

        def case_detail(moderation_case)
          Community::ModerationWorkbench::CaseDetail.call(
            actor: api_user,
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
          render_error("moderation_cases_not_found", status: :not_found)
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

        def moderation_request_id
          params[:request_id].presence || request.headers["Idempotency-Key"].presence
        end

        def requested_moderation_action
          request.request_parameters["action"].presence ||
            request.request_parameters[:action].presence
        end

        def render_workbench_error(result)
          payload = { error: result.error, errors: result.errors }
          payload[:data] = result.value if result.value.is_a?(Hash)
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
  end
end
