# frozen_string_literal: true

require "test_helper"

module Community
  class ReportAppealContractTest < ActiveSupport::TestCase
    test "external report contracts use public ids and role-isolated appeal routes" do
      routes = Rails.root.join("config/routes.rb").read
      reports = Rails.root.join("app/controllers/community/reports_controller.rb").read
      appeals = Rails.root.join("app/controllers/community/report_appeals_controller.rb").read
      frontend_routes = Rails.root.join("app/javascript/lib/routes.ts").read

      assert_includes routes, "resources :reports, only: %i[index show new create], param: :public_id"
      assert_includes routes, "resources :report_appeals,"
      assert_includes reports, "find_by!(public_id: params[:public_id])"
      assert_includes appeals, "where(appellant_id: current_user.id)"
      refute_match(/Community::Report\.find\(params\[:id\]\)/, reports)
      refute_match(/Community::ReportAppeal\.find\(params\[:id\]\)/, appeals)
      assert_includes frontend_routes, "forumReport: (publicId: string)"
    end

    test "draft upload submission remains same-subject clean and atomic" do
      draft = Rails.root.join("app/services/community/create_report_appeal_draft.rb").read
      submit = Rails.root.join("app/services/community/submit_report_appeal.rb").read
      binder = Rails.root.join("app/services/community/report_evidence_binder.rb").read
      registry = Rails.root.join("app/services/community/secure_evidence_subjects.rb").read

      assert_includes draft, 'status: "draft"'
      assert_includes draft, "ReportAppeal::DRAFT_TTL"
      assert_includes submit, 'subject_key: "community.report_appeal"'
      assert_operator submit.index("ReportEvidenceBinder.lock_clean!"), :<, submit.index("status: \"submitted\"")
      assert_includes binder, "attachment.uploader_id == actor.id"
      assert_includes binder, "upload&.scan_clean?"
      assert_includes registry, 'key: "community.report"'
      assert_includes registry, 'key: "community.report_appeal"'
      assert_includes registry, "max_files: ReportEvidenceBinder::MAX_ATTACHMENTS"
      assert_includes registry, "link.audience_appellant?"
      assert_includes submit, 'audience: "appellant"'
    end

    test "interrupted report evidence sealing remains recoverable to its reporter" do
      serializer = Rails.root.join("app/services/community/reporter_report_serializer.rb").read
      page = Rails.root.join("app/javascript/pages/Community/Reports/Show.vue").read

      assert_includes serializer, 'subject_key: "community.report"'
      assert_includes serializer, "sealed: false"
      assert_includes serializer, "AttachmentAccess.discard_allowed?"
      assert_includes page, "discardEvidence"
      assert_includes page, "sealEvidence(attachment)"
    end

    test "terminal decisions separate public outcome from internal notes and never auto reverse moderation" do
      decision = Rails.root.join("app/services/community/decide_report_appeal.rb").read
      public_serializer = Rails.root.join("app/services/community/report_appeal_serializer.rb").read
      review_serializer = Rails.root.join("app/services/community/report_appeal_review_serializer.rb").read

      assert_includes decision, 'moderation_reversal: "not_automatic"'
      assert_includes decision, "decision_idempotency_key_digest"
      assert_includes decision, "report_appeal_reviewer_conflict"
      refute_includes public_serializer, "internal_note"
      assert_includes review_serializer, "internal_note: @appeal.internal_note"
    end

    test "report and appeal records participate in data export without protected staff fields" do
      contributor = Rails.root.join(
        "app/services/community/report_identity_lifecycle/data_export_contributor.rb"
      ).read
      catalog = Rails.root.join("app/services/identity/core_data_export_contributors.rb").read

      assert_includes catalog, 'key: "community.report_cases"'
      assert_includes contributor, '"submitted_reports"'
      assert_includes contributor, '"appeals"'
      assert_includes contributor, '"account_actions"'
      serialized_keys = contributor.scan(/^\s+"([^"]+)"\s*=>/).flatten
      protected_staff_fields = %w[internal_note review_note reporter_id reviewer_id]
      assert_empty serialized_keys & protected_staff_fields
    end
  end
end
