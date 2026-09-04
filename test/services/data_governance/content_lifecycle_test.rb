# frozen_string_literal: true

require "test_helper"

module DataGovernance
  class ContentLifecycleTest < ActiveSupport::TestCase
    setup do
      @actor = create_user
      @author = create_user
      suffix = SecureRandom.hex(5)
      category = Community::Category.create!(
        name: "Governance #{suffix}",
        slug: "governance-#{suffix}"
      )
      @section = Community::Section.create!(
        category:,
        name: "Governance",
        slug: "governance-section-#{suffix}",
        position: 0
      )
      @topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: @section,
        user: @author,
        title: "Governed topic",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      @post = Community::Post.create!(
        topic: @topic,
        user: @author,
        floor_number: 1,
        body: "Governed post body",
        status: "published"
      )
      DataGovernance::RetentionPolicy.ensure_defaults!
      DataGovernance::RetentionPolicy.find_by!(resource_type: "Community::Post").update!(retention_days: 0)
    end

    test "soft deletion and restoration are reversible, audited, and idempotent" do
      deleted = DataGovernance::SoftDeleteContent.call(
        target: @post,
        actor: @actor,
        reason: "Remove personal data while the appeal window remains open.",
        request_id: "governance-delete-1",
        at: 1.minute.ago
      )
      replay = DataGovernance::SoftDeleteContent.call(
        target: @post,
        actor: @actor,
        reason: "Remove personal data while the appeal window remains open.",
        request_id: "governance-delete-1",
        at: 1.minute.ago
      )

      assert_predicate deleted, :success?, deleted.error
      assert_predicate replay, :success?, replay.error
      assert replay.value.fetch(:replayed)
      record = deleted.value.fetch(:record)
      assert_predicate @post.reload, :soft_deleted?
      assert_equal record.soft_deleted_at, @post.deleted_at
      assert_predicate record, :purge_due?
      assert_equal 1, AuditLog.where(action: "data_governance.content_soft_deleted",
                                     resource_type: "Community::Post",
                                     resource_id: @post.id).count

      restored = DataGovernance::RestoreContent.call(
        record:,
        actor: @actor,
        reason: "The deletion request was withdrawn.",
        request_id: "governance-restore-1"
      )
      restore_replay = DataGovernance::RestoreContent.call(
        record:,
        actor: @actor,
        reason: "The deletion request was withdrawn.",
        request_id: "governance-restore-1"
      )

      assert_predicate restored, :success?, restored.error
      assert restore_replay.value.fetch(:replayed)
      refute_predicate @post.reload, :soft_deleted?
      assert_predicate record.reload, :status_restored?
      assert_equal 1, AuditLog.where(action: "data_governance.content_restored",
                                     resource_type: "Community::Post",
                                     resource_id: @post.id).count
    end

    test "holds, unresolved reports, and active moderation evidence strictly block permanent purge" do
      record = soft_delete_post
      hold = DataGovernance::PlaceRetentionHold.call(
        target: @topic,
        actor: @actor,
        reason: "Preserve the complete topic evidence tree.",
        policy_reference: "MOD-100"
      ).value.fetch(:hold)
      report = Community::Report.create!(
        reporter: create_user,
        reportable: @post,
        reason_code: "offensive",
        reason: "Evidence must remain reviewable."
      )
      moderation_case = Community::ModerationCase.create!(
        source: @post,
        source_kind: "pending_post",
        status: "open",
        priority: "high",
        risk_level: "high",
        title: "Open evidence review",
        summary: "The source must not be destroyed.",
        source_updated_at: Time.current,
        section: @section,
        target_user: @author
      )

      blocked = DataGovernance::PermanentlyPurgeContent.call(
        record:,
        actor: @actor,
        reason: "Attempt cleanup after nominal retention expiry."
      )

      assert_predicate blocked, :failure?
      assert_equal "content_purge_blocked", blocked.code
      assert_includes blocked.value.fetch(:blockers), "legal_hold"
      assert_includes blocked.value.fetch(:blockers), "unresolved_report"
      assert_includes blocked.value.fetch(:blockers), "unresolved_moderation_case"
      assert Community::Post.with_discarded.exists?(@post.id)
      assert_equal blocked.value.fetch(:blockers).sort, record.reload.blocker_codes.sort

      DataGovernance::ReleaseRetentionHold.call(
        hold:,
        actor: @actor,
        reason: "Evidence hold transferred to the resolved case record."
      )
      report.update!(status: "dismissed", reviewer: @actor, reviewed_at: Time.current)
      moderation_case.update!(status: "resolved", resolved_at: Time.current)

      purged = DataGovernance::PermanentlyPurgeContent.call(
        record:,
        actor: @actor,
        reason: "All retention and evidence blockers have cleared."
      )

      assert_predicate purged, :success?, purged.error
      refute purged.value.fetch(:replayed)
      refute Community::Post.with_discarded.exists?(@post.id)
      assert_predicate record.reload, :status_purged?
      refute record.target_snapshot.key?("label")
      assert_equal 1, AuditLog.where(action: "data_governance.content_purged",
                                     resource_type: "Community::Post",
                                     resource_id: @post.id).count
      purge_audit = AuditLog.find_by!(
        action: "data_governance.content_purged",
        resource_type: "Community::Post",
        resource_id: @post.id
      )
      refute purge_audit.before_state.key?("label")
      refute_includes purge_audit.before_state.to_json, @post.body
    end

    test "scheduled cleanup is safe to run repeatedly" do
      record = soft_delete_post

      assert_changes -> { Community::Post.with_discarded.exists?(@post.id) }, from: true, to: false do
        Maintenance::PurgeGovernedContentJob.perform_now(at: Time.current)
      end
      assert_predicate record.reload, :status_purged?

      assert_no_changes -> { AuditLog.where(action: "data_governance.content_purged",
                                            resource_type: "Community::Post",
                                            resource_id: @post.id).count } do
        Maintenance::PurgeGovernedContentJob.perform_now(at: 1.hour.from_now)
      end
    end

    test "cleanup reconciles an already-missing target without retaining its content snapshot" do
      record = soft_delete_post
      deleted_body = @post.body
      @post.destroy!

      result = DataGovernance::PermanentlyPurgeContent.call(
        record:,
        actor: @actor,
        reason: "Reconcile a record removed outside the lifecycle service."
      )

      assert_predicate result, :success?, result.error
      assert result.value.fetch(:target_missing)
      assert_predicate record.reload, :status_purged?
      refute record.target_snapshot.key?("label")
      refute_includes record.target_snapshot.to_json, deleted_body
      audit = AuditLog
        .where(action: "data_governance.content_purged")
        .where("metadata ->> 'lifecycle_public_id' = ?", record.public_id)
        .first!
      assert_equal true, audit.metadata.fetch("target_missing")
    end

    test "topic cleanup permanently removes its dependent content as one aggregate" do
      attachment, attachment_upload, inline_upload = managed_uploads_for(@post)
      DataGovernance::RetentionPolicy.find_by!(resource_type: "Community::Topic").update!(retention_days: 0)
      deleted = DataGovernance::SoftDeleteContent.call(
        target: @topic,
        actor: @actor,
        reason: "The complete topic aggregate is due for deletion.",
        at: 1.minute.ago
      )

      assert_predicate deleted, :success?, deleted.error
      purged = nil
      assert_enqueued_jobs 2, only: Maintenance::CleanupForumUploadsJob do
        purged = DataGovernance::PermanentlyPurgeContent.call(
          record: deleted.value.fetch(:record),
          actor: @actor,
          reason: "The topic retention period elapsed without blockers."
        )
      end

      assert_predicate purged, :success?, purged.error
      refute Community::Topic.with_discarded.exists?(@topic.id)
      refute Community::Post.with_discarded.exists?(@post.id)
      refute Community::PostAttachment.with_discarded.exists?(attachment.id)
      assert_equal "cleanup_pending", attachment_upload.reload.status
      assert_nil attachment_upload.forum_post_id
      assert_equal "cleanup_pending", inline_upload.reload.status
      assert_nil inline_upload.forum_post_id
    end

    test "post cleanup schedules attachment and inline upload ledgers before destroy" do
      attachment, attachment_upload, inline_upload = managed_uploads_for(@post)
      record = soft_delete_post
      purged = nil

      assert_enqueued_jobs 2, only: Maintenance::CleanupForumUploadsJob do
        purged = DataGovernance::PermanentlyPurgeContent.call(
          record:,
          actor: @actor,
          reason: "The post retention period elapsed without blockers."
        )
      end

      assert_predicate purged, :success?, purged.error
      refute Community::Post.with_discarded.exists?(@post.id)
      refute Community::PostAttachment.with_discarded.exists?(attachment.id)
      assert_equal "cleanup_pending", attachment_upload.reload.status
      assert_nil attachment_upload.forum_post_id
      assert_equal "cleanup_pending", inline_upload.reload.status
      assert_nil inline_upload.forum_post_id
    end

    test "account closure can never permanently purge a shared topic container" do
      other_post = Community::Post.create!(
        topic: @topic,
        user: create_user,
        floor_number: 2,
        body: "Another author's reply must survive",
        status: "published"
      )
      record = create_legacy_structural_lifecycle(@topic)

      purged = DataGovernance::PermanentlyPurgeContent.call(
        record:,
        actor: @actor,
        reason: "Scheduled account closure cleanup"
      )

      assert_predicate purged, :failure?
      assert_includes purged.value.fetch(:blockers), "account_closure_shared_container"
      assert Community::Topic.with_discarded.exists?(@topic.id)
      assert Community::Post.with_discarded.exists?(other_post.id)
    end

    test "account closure cannot purge opening posts or profile wall containers" do
      wall_owner = create_user
      wall_post = Community::ProfilePost.create!(
        profile_user: wall_owner,
        author: @author,
        body: "Shared wall container",
        status: "published"
      )
      retained_comment = Community::ProfilePostComment.create!(
        profile_post: wall_post,
        author: create_user,
        body: "Another member's comment",
        status: "published"
      )
      records = [
        create_legacy_structural_lifecycle(@post),
        create_legacy_structural_lifecycle(wall_post)
      ]

      records.each do |record|
        purged = DataGovernance::PermanentlyPurgeContent.call(
          record:,
          actor: @actor,
          reason: "Attempt to bypass structural account-closure preservation."
        )
        assert_predicate purged, :failure?
        assert_includes purged.value.fetch(:blockers), "account_closure_shared_container"
      end

      assert Community::Post.with_discarded.exists?(@post.id)
      assert Community::ProfilePost.with_discarded.exists?(wall_post.id)
      assert Community::ProfilePostComment.with_discarded.exists?(retained_comment.id)
    end

    test "soft deletion rejects new account closure lifecycles for structural containers" do
      wall_post = Community::ProfilePost.create!(
        profile_user: create_user,
        author: @author,
        body: "Shared wall container",
        status: "published"
      )

      [ @topic, @post, wall_post ].each do |target|
        result = DataGovernance::SoftDeleteContent.call(
          target:,
          actor: @author,
          reason: "account_closure_delete_content"
        )

        assert_predicate result, :failure?
        assert_equal "account_closure_structural_container_requires_tombstone",
                     result.code
        refute_predicate target.reload, :soft_deleted?
        refute DataGovernance::ContentLifecycleRecord.exists?(
          target_type: target.class.base_class.name,
          target_id: target.id
        )
      end
    end

    test "a hold on any reply author blocks permanent cleanup of the whole topic" do
      reply_author = create_user
      reply = Community::Post.create!(
        topic: @topic,
        user: reply_author,
        floor_number: 2,
        body: "Reply covered by an account-level retention hold.",
        status: "published"
      )
      hold = DataGovernance::PlaceRetentionHold.call(
        target: reply_author,
        actor: @actor,
        reason: "Preserve every contribution by this account."
      )
      DataGovernance::RetentionPolicy.find_by!(resource_type: "Community::Topic").update!(retention_days: 0)
      deleted = DataGovernance::SoftDeleteContent.call(
        target: @topic,
        actor: @actor,
        reason: "The topic aggregate entered its retention window.",
        at: 1.minute.ago
      )

      assert_predicate hold, :success?, hold.error
      assert_predicate deleted, :success?, deleted.error
      blocked = DataGovernance::PermanentlyPurgeContent.call(
        record: deleted.value.fetch(:record),
        actor: @actor,
        reason: "Attempt aggregate cleanup while one author is held."
      )

      assert_predicate blocked, :failure?
      assert_includes blocked.value.fetch(:blockers), "legal_hold"
      assert Community::Topic.with_discarded.exists?(@topic.id)
      assert Community::Post.with_discarded.exists?(reply.id)
    end

    test "topic deletion policy evaluates descendant evidence through bounded SQL references" do
      reply_author = create_user
      attachment_author = create_user
      reply = Community::Post.create!(
        topic: @topic,
        user: reply_author,
        floor_number: 2,
        body: "Reply with governed attachment evidence.",
        status: "published"
      )
      attachment = Community::PostAttachment.create!(
        post: reply,
        user: attachment_author,
        filename: "evidence.txt",
        byte_size: 128
      )
      hold = DataGovernance::PlaceRetentionHold.call(
        target: attachment_author,
        actor: @actor,
        reason: "Preserve evidence owned by this account."
      )
      report = Community::Report.create!(
        reporter: create_user,
        reportable: attachment,
        reason_code: "offensive",
        reason: "Attachment requires review."
      )
      Community::ModerationCase.create!(
        source: report,
        source_kind: "report",
        status: "open",
        priority: "high",
        risk_level: "high",
        title: "Attachment report review",
        summary: "Keep the aggregate until review completes.",
        source_updated_at: Time.current,
        section: @section,
        target_user: attachment_author
      )

      evidence_references = DataGovernance::ContentRegistry.evidence_reference_sets(@topic)
      post_ids = evidence_references.find { |reference| reference.target_type == "Community::Post" }
      attachment_ids = evidence_references.find do |reference|
        reference.target_type == "Community::PostAttachment"
      end
      assert_kind_of ActiveRecord::Relation, post_ids.target_ids
      assert_kind_of ActiveRecord::Relation, attachment_ids.target_ids
      refute_predicate post_ids.target_ids, :loaded?
      refute_predicate attachment_ids.target_ids, :loaded?
      assert_predicate hold, :success?, hold.error

      reject_materialization = ->(*) { flunk("deletion policy loaded aggregate records") }
      result = DataGovernance::ContentRegistry.stub(:evidence_targets, reject_materialization) do
        DataGovernance::ContentRegistry.stub(:hold_targets, reject_materialization) do
          DataGovernance::DeletionPolicy.call(target: @topic)
        end
      end

      assert_predicate result, :success?, result.error
      assert_includes result.value.fetch(:blockers), "legal_hold"
      assert_includes result.value.fetch(:blockers), "unresolved_report"
      assert_includes result.value.fetch(:blockers), "unresolved_moderation_case"
    end

    test "an open payment dispute blocks deletion policy for the affected account" do
      order = Commerce::Order.create!(
        user: @author,
        status: "completed",
        currency: "CNY",
        subtotal_cents: 1_000,
        total_cents: 1_000
      )
      payment = Payments::Record.create!(
        order:,
        provider: "fake",
        provider_payment_id: "governance_#{SecureRandom.hex(8)}",
        status: "succeeded",
        amount_cents: 1_000,
        currency: "CNY"
      )
      Commerce::Dispute.create!(
        order:,
        payment_record: payment,
        provider: "fake",
        provider_dispute_id: "dp_#{SecureRandom.hex(8)}",
        status: "open",
        risk_level: "high",
        rights_status: "unchanged",
        amount_cents: 1_000,
        liability_cents: 1_000,
        offset_cents: 0,
        currency: "CNY"
      )

      result = DataGovernance::DeletionPolicy.call(target: @author)

      refute result.value.fetch(:allowed)
      assert_includes result.value.fetch(:blockers), "open_dispute"
    end

    test "community content without a commerce dispute scope evaluates safely" do
      result = DataGovernance::DeletionPolicy.call(target: @post)

      assert_predicate result, :success?, result.error
      assert_equal true, result.value.fetch(:allowed)
      refute_includes result.value.fetch(:blockers), "open_dispute"
    end

    test "policy changes reschedule pending cleanup and cannot strand active holds" do
      record = soft_delete_post
      policy = DataGovernance::RetentionPolicy.find_by!(resource_type: "Community::Post")

      changed = DataGovernance::UpdateRetentionPolicy.call(
        policy:,
        actor: @actor,
        attributes: { retention_days: 45 },
        reason: "Extend the recovery window after a policy review.",
        request_id: "policy-change-1"
      )

      assert_predicate changed, :success?, changed.error
      assert_in_delta record.soft_deleted_at + 45.days, record.reload.purge_after, 1.second
      assert_equal 1, AuditLog.where(
        action: "data_governance.retention_policy_updated",
        resource_type: "DataGovernance::RetentionPolicy",
        resource_id: policy.id
      ).count

      DataGovernance::PlaceRetentionHold.call(
        target: @post,
        actor: @actor,
        reason: "Preserve evidence during policy review."
      )
      rejected = DataGovernance::UpdateRetentionPolicy.call(
        policy:,
        actor: @actor,
        attributes: { legal_hold_supported: false },
        reason: "Attempt to disable holds."
      )

      assert_predicate rejected, :failure?
      assert_equal "active_retention_holds_exist", rejected.code
      assert_predicate policy.reload, :legal_hold_supported?
    end

    test "every registered community resource has an unambiguous soft-deletion column" do
      DataGovernance::ContentRegistry.entries.each do |entry|
        model = entry.model_name.constantize
        assert_includes model.column_names, "deleted_at", entry.type
        assert_respond_to model.new, :soft_deleted?, entry.type
      end
    end

    private

    def managed_uploads_for(post)
      attachment = Community::PostAttachment.create!(
        post:,
        user: @author,
        filename: "governed.txt",
        content_type: "text/plain",
        byte_size: 16
      )
      attachment_upload = Community::Upload.create!(
        user: @author,
        public_id: Community::Upload.generate_public_id,
        kind: "post_attachment",
        status: "linked",
        scan_status: "clean",
        byte_size: 16,
        post:,
        post_attachment: attachment
      )
      inline_upload = Community::Upload.create!(
        user: @author,
        public_id: Community::Upload.generate_public_id,
        kind: "inline_image",
        status: "linked",
        scan_status: "clean",
        byte_size: 16,
        post:
      )
      [ attachment, attachment_upload, inline_upload ]
    end

    def create_legacy_structural_lifecycle(target)
      at = 1.minute.ago
      snapshot = DataGovernance::ContentRegistry.snapshot(target)
      target.soft_delete!(at:)
      DataGovernance::ContentLifecycleRecord.create!(
        target_type: target.class.base_class.name,
        target_id: target.id,
        status: "soft_deleted",
        deleted_by: @author,
        soft_deleted_at: at,
        purge_after: at,
        deletion_reason: "account_closure_delete_content",
        target_snapshot: snapshot
      )
    end

    def soft_delete_post
      result = DataGovernance::SoftDeleteContent.call(
        target: @post,
        actor: @actor,
        reason: "Retention lifecycle test.",
        at: 1.minute.ago
      )
      assert_predicate result, :success?, result.error
      result.value.fetch(:record)
    end
  end
end
