# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class CommunityReportCaseCenterTest < ActionDispatch::IntegrationTest
  include InertiaRails::Minitest

  setup do
    @reporter = create_user
    @stranger = create_user
    target = create_user
    result = Community::CreateReport.call(
      reporter: @reporter,
      reportable_type: "User",
      reportable_id: target.id,
      reason_code: "offensive",
      reason_detail: "Reporter-only detail",
      ip_address: "127.0.0.1"
    )
    assert_predicate result, :success?, result.error
    @report = result.value
  end

  test "index and detail expose only the reporter safe contract" do
    sign_in_as(@reporter)

    get forum_reports_path
    assert_response :success
    assert_private_report_response
    reports = inertia.props.deep_symbolize_keys.fetch(:reports)
    assert_equal [ @report.public_id ], reports.pluck(:id)

    get forum_report_path(@report)
    assert_response :success
    assert_private_report_response
    report = inertia.props.deep_symbolize_keys.fetch(:report)
    assert_equal @report.public_id, report.fetch(:id)
    assert_equal "Reporter-only detail", report.fetch(:reason_detail)
    assert_equal I18n.t("mcweb.forum.reports.targets.user", locale: @reporter.locale), report.fetch(:target_label)
    assert_empty report.keys & %i[
      reviewer reviewer_id review_note assignee evidence reportable reportable_id
      other_reporters moderation_action penalty duration member_status
    ]
  end

  test "another account receives a private 404 for detail and mutations" do
    sign_in_as(@stranger)

    get forum_report_path(@report)
    assert_response :not_found
    assert_private_report_response

    post supplements_forum_report_path(@report), params: {
      supplement: {
        body: "Not mine",
        lock_version: @report.lock_version,
        idempotency_key: SecureRandom.uuid
      }
    }
    assert_response :not_found
    assert_private_report_response

    patch withdraw_forum_report_path(@report), params: {
      report: {
        desired_state: "withdrawn",
        lock_version: @report.lock_version,
        idempotency_key: SecureRandom.uuid
      }
    }
    assert_response :not_found
    assert_private_report_response
    assert_predicate @report.reload, :pending?
  end

  private

  def assert_private_report_response
    assert_includes response.headers.fetch("Cache-Control"), "private"
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_equal "noindex, nofollow", response.headers.fetch("X-Robots-Tag")
  end
end
