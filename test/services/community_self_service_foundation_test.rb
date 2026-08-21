# frozen_string_literal: true

require "test_helper"

class CommunitySelfServiceFoundationTest < ActiveSupport::TestCase
  setup do
    @sender = create_user
    @recipient = create_user
    @outsider = create_user
    @conversation = Community::Conversation.create!
    @conversation.participants.create!(user: @sender)
    @conversation.participants.create!(user: @recipient)
    @message = @conversation.messages.create!(
      user: @sender,
      body: "private evidence #{SecureRandom.hex(8)}"
    )
  end

  test "private-message reports capture encrypted immutable evidence without leaking body into audit" do
    result = Community::CreateReport.call(
      reporter: @recipient,
      reportable_type: "Community::Message",
      reportable_id: @message.id,
      reason_code: "spam",
      reason_detail: "Repeated unsolicited contact"
    )

    assert_predicate result, :success?, result.error
    report = result.value
    evidence = report.evidence
    assert_equal "spam", report.reason_code
    assert_equal "Repeated unsolicited contact", report.reason
    assert_equal @message.body, evidence.snapshot.fetch("body")
    assert_equal @message.revision, evidence.subject_revision
    assert_predicate evidence, :digest_valid?
    refute_includes evidence.encrypted_snapshot, @message.body

    audit = AuditLog.by_action("community.report_created").find_by!(resource_id: report.id)
    serialized_audit = JSON.generate(
      metadata: audit.metadata,
      before_state: audit.before_state,
      after_state: audit.after_state
    )
    refute_includes serialized_audit, @message.body

    assert_raises ActiveRecord::StatementInvalid do
      Community::ReportEvidence.transaction(requires_new: true) do
        Community::ReportEvidence.where(id: evidence.id).update_all(captured_at: 1.minute.ago)
      end
    end
    assert_raises ActiveRecord::StatementInvalid do
      Community::ReportEvidence.transaction(requires_new: true) do
        Community::ReportEvidence.where(id: evidence.id).delete_all
      end
    end
    assert Community::ReportEvidence.exists?(evidence.id)
  end

  test "private-message report requires a recipient and deduplicates pending reports" do
    outsider_result = Community::CreateReport.call(
      reporter: @outsider,
      reportable_type: "Community::Message",
      reportable_id: @message.id,
      reason_code: "spam"
    )
    assert_predicate outsider_result, :failure?
    assert_equal "report_target_unavailable", outsider_result.code

    self_result = Community::CreateReport.call(
      reporter: @sender,
      reportable_type: "Community::Message",
      reportable_id: @message.id,
      reason_code: "spam"
    )
    assert_predicate self_result, :failure?
    assert_equal "report_target_unavailable", self_result.code

    first = Community::CreateReport.call(
      reporter: @recipient,
      reportable_type: "Community::Message",
      reportable_id: @message.id,
      reason_code: "spam"
    )
    assert_predicate first, :success?, first.error

    duplicate = Community::CreateReport.call(
      reporter: @recipient,
      reportable_type: "Community::Message",
      reportable_id: @message.id,
      reason_code: "spam"
    )
    assert_predicate duplicate, :failure?
    assert_equal "report_already_submitted", duplicate.code
  end

  test "message revisions are encrypted append-only and cascade only with permanent message deletion" do
    initial = @message.revisions.find_by!(revision: 1)
    assert_equal @message.body, initial.body
    assert_predicate initial, :digest_valid?
    refute_includes initial.encrypted_body, @message.body

    result = Community::EditMessage.call(
      user: @sender,
      message: @message,
      body: "corrected private message",
      expected_revision: 1
    )
    assert_predicate result, :success?, result.error
    assert_equal 2, @message.reload.revision
    assert_equal [ 1, 2 ], @message.revisions.order(:revision).pluck(:revision)
    assert_equal "corrected private message", @message.revisions.find_by!(revision: 2).body

    stale = Community::EditMessage.call(
      user: @sender,
      message: @message,
      body: "stale overwrite",
      expected_revision: 1
    )
    assert_predicate stale, :failure?
    assert_equal "message_revision_conflict", stale.code
    assert_equal "corrected private message", @message.reload.body

    revision = @message.revisions.find_by!(revision: 1)
    assert_raises ActiveRecord::StatementInvalid do
      Community::MessageRevision.transaction(requires_new: true) do
        Community::MessageRevision.where(id: revision.id).update_all(content_digest: "0" * 64)
      end
    end
    assert_raises ActiveRecord::StatementInvalid do
      Community::MessageRevision.transaction(requires_new: true) do
        Community::MessageRevision.where(id: revision.id).delete_all
      end
    end

    revision_ids = @message.revisions.pluck(:id)
    @message.destroy!
    assert_empty Community::MessageRevision.where(id: revision_ids)
  end

  test "data-governance purge removes a message and its revisions after retention expires" do
    DataGovernance::RetentionPolicy.ensure_defaults!
    DataGovernance::RetentionPolicy
      .find_by!(resource_type: "Community::Message")
      .update!(retention_days: 0)
    edited = Community::EditMessage.call(
      user: @sender,
      message: @message,
      body: "Second retained revision",
      expected_revision: 1
    )
    assert_predicate edited, :success?, edited.error
    revision_ids = @message.revisions.pluck(:id)

    deleted = DataGovernance::SoftDeleteContent.call(
      target: @message,
      actor: @sender,
      reason: "The sender requested deletion.",
      at: 1.minute.ago
    )
    assert_predicate deleted, :success?, deleted.error

    purged = DataGovernance::PermanentlyPurgeContent.call(
      record: deleted.value.fetch(:record),
      actor: @sender,
      reason: "The configured retention period has elapsed."
    )

    assert_predicate purged, :success?, purged.error
    refute Community::Message.with_discarded.exists?(@message.id)
    assert_empty Community::MessageRevision.where(id: revision_ids)
    assert_predicate deleted.value.fetch(:record).reload, :status_purged?
  end
end
