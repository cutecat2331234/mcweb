# frozen_string_literal: true

require "test_helper"
require "tempfile"

module Commerce
  class CustomerDisputeSecureEvidenceTest < ActiveSupport::TestCase
    setup do
      @owner = create_user
      @other = create_user
      @ordinary_staff = create_user
      @sensitive_staff = create_user
      grant_permission(@sensitive_staff, "store.disputes.sensitive_read")
      @order = Commerce::Order.create!(
        user: @owner,
        status: "completed",
        subtotal_cents: 1_000,
        total_cents: 1_000,
        currency: "CNY"
      )
      Payments::Record.create!(
        order: @order,
        provider: "fake",
        provider_payment_id: "secure_dispute_#{SecureRandom.hex(8)}",
        status: "succeeded",
        amount_cents: 1_000,
        currency: "CNY"
      )
      @dispute = Commerce::Disputes::CreateCustomerDispute.call(
        order: @order,
        actor: @owner,
        request_id: SecureRandom.uuid,
        reason_kind: "other",
        description: "I need to provide retained payment evidence.",
        amount_cents: 500
      ).value.fetch(:dispute)

      registry = SecureEvidence::SubjectRegistry.new
      Commerce::SecureEvidenceSubjects::REGISTRAR.call(registry)
      @entry = registry.entry_for_key(Commerce::SecureEvidenceSubjects::SUBJECT_KEY)
      @catalog = Struct.new(:entry) do
        def entry_for_key(_key) = entry
      end.new(@entry)
    end

    test "owner uploads while staff access requires the sensitive permission" do
      result = SecureEvidence::CreateAttachment.call(
        actor: @owner,
        subject_key: @entry.key,
        subject_public_id: @dispute.public_id,
        file: upload("customer payment evidence"),
        idempotency_key: "commerce-dispute-evidence-0001",
        catalog: @catalog
      )

      assert_predicate result, :success?, result.error
      attachment = result.value.fetch(:attachment)
      assert SecureEvidence::AttachmentAccess.subject_download_allowed?(
        attachment,
        actor: @owner,
        catalog: @catalog
      )
      assert SecureEvidence::AttachmentAccess.subject_download_allowed?(
        attachment,
        actor: @sensitive_staff,
        catalog: @catalog
      )
      assert_not SecureEvidence::AttachmentAccess.subject_download_allowed?(
        attachment,
        actor: @ordinary_staff,
        catalog: @catalog
      )
      assert_not SecureEvidence::AttachmentAccess.subject_download_allowed?(
        attachment,
        actor: @other,
        catalog: @catalog
      )
      assert_not SecureEvidence::AttachmentAccess.discard_allowed?(
        attachment,
        actor: @owner,
        catalog: @catalog
      )
    ensure
      @temporary_file&.close!
    end

    test "foreign and terminal cases reject new uploads while retaining existing evidence" do
      first = SecureEvidence::CreateAttachment.call(
        actor: @owner,
        subject_key: @entry.key,
        subject_public_id: @dispute.public_id,
        file: upload("retained evidence"),
        idempotency_key: "commerce-dispute-evidence-0002",
        catalog: @catalog
      )
      assert_predicate first, :success?, first.error

      foreign = SecureEvidence::CreateAttachment.call(
        actor: @other,
        subject_key: @entry.key,
        subject_public_id: @dispute.public_id,
        file: upload("foreign evidence"),
        idempotency_key: "commerce-dispute-evidence-0003",
        catalog: @catalog
      )
      assert_predicate foreign, :failure?
      assert_equal "secure_evidence_subject_unavailable", foreign.code

      withdrawn = Commerce::Disputes::WithdrawCustomerDispute.call(
        order: @order,
        dispute: @dispute,
        actor: @owner,
        request_id: SecureRandom.uuid
      )
      assert_predicate withdrawn, :success?, withdrawn.error

      terminal = SecureEvidence::CreateAttachment.call(
        actor: @owner,
        subject_key: @entry.key,
        subject_public_id: @dispute.public_id,
        file: upload("late evidence"),
        idempotency_key: "commerce-dispute-evidence-0004",
        catalog: @catalog
      )
      assert_predicate terminal, :failure?
      assert_equal "secure_evidence_subject_unavailable", terminal.code
      assert SecureEvidence::Attachment.exists?(id: first.value.fetch(:attachment).id)
    ensure
      @temporary_file&.close!
    end

    private

    def upload(content)
      @temporary_file&.close!
      @temporary_file = Tempfile.new([ "commerce-dispute-evidence", ".txt" ])
      @temporary_file.binmode
      @temporary_file.write(content)
      @temporary_file.rewind
      Rack::Test::UploadedFile.new(
        @temporary_file.path,
        "text/plain",
        original_filename: "payment-evidence.txt"
      )
    end
  end
end
