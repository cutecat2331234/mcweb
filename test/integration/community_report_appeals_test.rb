# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class CommunityReportAppealsTest < ActionDispatch::IntegrationTest
  include InertiaRails::Minitest

  setup do
    @reporter = create_user
    @affected_user = create_user
    @reviewer = create_user
    grant_permission(@reviewer, "forum.topics.lock")
    created = Community::CreateReport.call(
      reporter: @reporter,
      reportable_type: "User",
      reportable_id: @affected_user.id,
      reason_code: "offensive",
      reason_detail: "Reporter-private context",
      ip_address: "127.0.0.1"
    )
    assert_predicate created, :success?, created.error
    @report = created.value
    decided = Community::DecideReport.call(
      report: @report,
      reviewer: @reviewer,
      desired_status: "dismissed",
      idempotency_key: SecureRandom.uuid,
      expected_version: @report.lock_version
    )
    assert_predicate decided, :success?, decided.error
    @report.reload
  end

  test "reporter creates a private draft and submits it through public ids" do
    sign_in_as(@reporter)

    get forum_report_appeals_path
    assert_response :success
    available = inertia.props.deep_symbolize_keys.fetch(:eligible_reports)
    assert_equal [ [ @report.public_id, "reporter" ] ], available.pluck(:public_id, :appellant_role)

    post appeal_draft_forum_report_path(@report), params: {
      appeal: { appellant_role: "reporter", idempotency_key: SecureRandom.uuid }
    }
    appeal = Community::ReportAppeal.find_by!(report: @report, appellant: @reporter)
    assert_redirected_to forum_report_appeal_path(appeal)
    assert_not_equal appeal.id.to_s, appeal.to_param

    get forum_report_appeal_path(appeal)
    assert_response :success
    assert_private_response
    payload = inertia.props.deep_symbolize_keys.fetch(:appeal)
    assert_equal appeal.public_id, payload.fetch(:public_id)
    assert_equal({ key: "community.report_appeal", public_id: appeal.public_id }, payload.fetch(:evidence_subject))
    assert_empty payload.keys & %i[internal_note reviewer reporter]

    patch submit_forum_report_appeal_path(appeal), params: {
      appeal: {
        reason: "Please review the completed decision",
        attachment_public_ids: [],
        idempotency_key: SecureRandom.uuid,
        lock_version: appeal.lock_version
      }
    }
    assert_redirected_to forum_report_appeal_path(appeal)
    assert_predicate appeal.reload, :submitted?
  end

  test "another account receives the same private not found response for an appeal" do
    appeal = create_submitted_appeal
    sign_in_as(create_user)

    get forum_report_appeal_path(appeal)
    assert_response :not_found
    assert_private_response

    get forum_report_appeal_path(appeal.id)
    assert_response :not_found
    assert_private_response
  end

  test "authorized staff queue exposes protected context only inside staff" do
    appeal = create_submitted_appeal
    sign_in_as(@reviewer)

    get staff_report_appeals_path
    assert_response :success
    rows = inertia.props.deep_symbolize_keys.fetch(:appeals)
    assert_equal [ appeal.public_id ], rows.pluck(:public_id)

    get staff_report_appeal_path(appeal)
    assert_response :success
    payload = inertia.props.deep_symbolize_keys.fetch(:appeal)
    assert_equal @reporter.username, payload.dig(:internal_case, :reporter)
    assert_equal "Reporter-private context", payload.dig(:internal_case, :report_reason_detail)
  end

  private

  def create_submitted_appeal
    drafted = Community::CreateReportAppealDraft.call(
      report: @report,
      appellant: @reporter,
      appellant_role: "reporter",
      idempotency_key: SecureRandom.uuid
    )
    assert_predicate drafted, :success?, drafted.error
    appeal = drafted.value.fetch(:appeal)
    submitted = Community::SubmitReportAppeal.call(
      appeal:,
      appellant: @reporter,
      reason: "Please review the completed decision",
      attachment_public_ids: [],
      idempotency_key: SecureRandom.uuid,
      expected_version: appeal.lock_version
    )
    assert_predicate submitted, :success?, submitted.error
    appeal.reload
  end

  def assert_private_response
    assert_includes response.headers.fetch("Cache-Control"), "private"
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_equal "noindex, nofollow", response.headers.fetch("X-Robots-Tag")
  end
end
