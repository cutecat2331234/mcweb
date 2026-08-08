# frozen_string_literal: true

module Staff
  class DashboardController < BaseController
    def index
      sync_result = Community::ModerationWorkbench::SyncCases.call
      visible = staff_moderation_policy.visible_scope
      active = visible.where(status: Community::ModerationCase::ACTIVE_STATUSES)
      queue = Community::ModerationWorkbench::Queue.new(
        actor: current_user,
        filters: { status: "active" }
      )

      render inertia: "Staff/Dashboard/Index", props: {
        metrics: {
          active: active.count,
          unassigned: active.where(assignee_id: nil).count,
          assigned_to_me: active.where(assignee_id: current_user.id).count,
          high_risk: active.where(risk_level: %w[high critical]).count
        },
        source_counts: active.group(:source_kind).count,
        recent_cases: queue.relation.limit(8).map { |record| queue.serialize(record) },
        links: {
          queue: staff_moderation_cases_path,
          my_queue: staff_moderation_cases_path(assignee_id: "me"),
          unassigned: staff_moderation_cases_path(assignee_id: "unassigned"),
          high_risk: staff_moderation_cases_path(risk_level: "high")
        },
        sync_warning: sync_result.failure? ? sync_result.error : nil
      }
    end
  end
end
