# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class IdentityDataExportsTest < ActionDispatch::IntegrationTest
  include InertiaRails::Minitest

  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "signed-in user can open and queue an export without a full page contract" do
    get identity_data_exports_path

    assert_response :success
    assert_equal "Identity/DataExports/Index", inertia.component
    assert_equal [], inertia.props.fetch(:exports)
    assert_equal false, inertia.props.dig(:pagination, :has_more)

    assert_enqueued_jobs 1, only: Identity::BuildDataExportJob do
      post identity_data_exports_path, params: {
        data_export: { idempotency_key: "integration-export-1" }
      }
    end

    assert_redirected_to identity_data_exports_path
    assert Identity::DataExport.exists?(user: @user, idempotency_key: "integration-export-1")
  end

  test "download is owner scoped private and unavailable after revocation" do
    data_export = Identity::DataExport.create!(
      user: @user,
      idempotency_key: "integration-download-1",
      requested_at: Time.current,
      status: :completed,
      completed_at: Time.current,
      expires_at: 1.hour.from_now
    )
    data_export.archive.attach(
      io: StringIO.new("private export"),
      filename: "mcweb-export.zip",
      content_type: "application/zip"
    )

    get download_identity_data_export_path(data_export)

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_includes response.headers["Content-Disposition"], "mcweb-export.zip"
    assert_equal "private export", response.body

    delete revoke_identity_data_export_path(data_export)
    assert_redirected_to identity_data_exports_path

    get download_identity_data_export_path(data_export)
    assert_redirected_to identity_data_exports_path
  end

  test "another user cannot infer export existence" do
    other = create_user
    data_export = Identity::DataExport.create!(
      user: other,
      idempotency_key: "other-export-1",
      requested_at: Time.current
    )

    get download_identity_data_export_path(data_export)

    assert_response :not_found
  end

  test "cursor pagination makes the complete export history reachable without duplicates" do
    requested_at = Time.zone.parse("2026-08-22 12:00:00 UTC")
    57.times do |index|
      Identity::DataExport.create!(
        user: @user,
        idempotency_key: "history-export-#{index}",
        requested_at: requested_at - index.seconds
      )
    end

    ids = []
    cursor = nil
    loop do
      get identity_data_exports_path, params: { cursor: }.compact

      assert_response :success
      page_ids = inertia.props.fetch(:exports).map { |item| item.fetch(:id) }
      assert_operator page_ids.length, :<=, Identity::DataExportsController::PAGE_SIZE
      ids.concat(page_ids)
      pagination = inertia.props.fetch(:pagination)
      break unless pagination.fetch(:has_more)

      cursor = pagination.fetch(:next_cursor)
      assert cursor.present?
    end

    assert_equal 57, ids.length
    assert_equal 57, ids.uniq.length
    assert_equal Identity::DataExport.where(user: @user).recent_first.pluck(:public_id), ids
  end

  test "cursor is owner scoped" do
    other = create_user
    data_export = Identity::DataExport.create!(
      user: other,
      idempotency_key: "other-cursor-export",
      requested_at: Time.current
    )

    get identity_data_exports_path, params: { cursor: data_export.public_id }

    assert_response :not_found
  end
end
