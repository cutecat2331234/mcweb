# frozen_string_literal: true

require "test_helper"

module Identity
  module AccountClosure
    class AuthoredContentDeletionTest < ActiveSupport::TestCase
      setup do
        @user = create_user
        @conversation = Community::Conversation.create!(title: "Closure messages")
        Community::ConversationParticipant.create!(conversation: @conversation, user: @user)
      end

      test "a large closure is advanced by bounded durable batches" do
        (AuthoredContentDeletion::BATCH_SIZE + 1).times do |index|
          Community::Message.create!(
            conversation: @conversation,
            user: @user,
            body: "Message #{index}"
          )
        end

        result = close_with_content_deletion
        assert_predicate result, :success?

        first_intent = deletion_intents.first
        first_result = AuthoredContentDeletion.execute(first_intent)

        assert_equal "succeeded", first_result.status
        assert_equal "authored_content_deletion_queued", @user.reload.account_closure_outcome
        assert_equal AuthoredContentDeletion::BATCH_SIZE,
                     DataGovernance::ContentLifecycleRecord
                       .where(target_type: "Community::Message")
                       .count
        assert_equal 2, deletion_intents.count

        second_result = AuthoredContentDeletion.execute(deletion_intents.last)

        assert_equal "succeeded", second_result.status
        assert_equal "authored_content_deleted", @user.reload.account_closure_outcome
        assert_equal AuthoredContentDeletion::BATCH_SIZE + 1,
                     DataGovernance::ContentLifecycleRecord
                       .where(target_type: "Community::Message")
                       .count
      end

      test "replaying a completed durable request cannot duplicate lifecycle or completion audit" do
        message = Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Delete once"
        )
        close_with_content_deletion
        intent = deletion_intents.first

        first = AuthoredContentDeletion.execute(intent)
        replay = AuthoredContentDeletion.execute(intent)

        assert_equal "succeeded", first.status
        assert_equal "skipped", replay.status
        assert_equal 1, DataGovernance::ContentLifecycleRecord.where(
          target_type: "Community::Message",
          target_id: message.id
        ).count
        assert_equal 1, AuditLog.where(
          action: "identity.account_closure_content_completed",
          resource_id: @user.id
        ).count
      end

      test "a completed batch finalizer is an idempotent no-op" do
        close_with_content_deletion
        intent = deletion_intents.first

        completed = AuthoredContentDeletion.execute(intent)
        replayed_finalize = AuthoredContentDeletion.finalize!(
          user: @user,
          request_key: intent.arguments.fetch("request_key"),
          batch_number: intent.arguments.fetch("batch_number")
        )

        assert_equal "succeeded", completed.status
        assert_nil replayed_finalize
        assert_equal 1, AuditLog.where(
          action: "identity.account_closure_content_completed",
          resource_id: @user.id
        ).count
      end

      test "a superseded batch cannot delete content owned by its successor" do
        message = Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Successor-owned cursor"
        )
        close_with_content_deletion
        intent = deletion_intents.first
        results = @user.reload.account_closure_results.deep_dup
        processing = results.dig("identity.authored_content", "details", "processing")
        processing["batch_number"] = intent.arguments.fetch("batch_number") + 1
        @user.update!(account_closure_results: results)

        outcome = AuthoredContentDeletion.process_one!(
          user: @user,
          request_key: intent.arguments.fetch("request_key"),
          batch_number: intent.arguments.fetch("batch_number"),
          resource_key: "messages",
          target_id: message.id
        )

        assert_equal :superseded, outcome
        refute_predicate Community::Message.find(message.id), :soft_deleted?
      end

      test "content blockers are retained and reported without reversing account closure" do
        message = Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Held evidence"
        )
        actor = create_user
        hold = DataGovernance::PlaceRetentionHold.call(
          target: message,
          actor:,
          reason: "Preserve evidence during an investigation."
        )
        assert_predicate hold, :success?

        close_with_content_deletion
        AuthoredContentDeletion.execute(deletion_intents.first)

        assert_equal "legally_retained", @user.reload.account_closure_outcome
        refute Community::Message.with_discarded.find(message.id).soft_deleted?
        assert_equal 1,
                     @user.account_closure_results
                       .dig("identity.authored_content", "details", "retained_records", "messages")
        assert_equal 1,
                     @user.account_closure_results
                       .dig("identity.authored_content", "details", "blocker_counts", "legal_hold")
        processing = @user.account_closure_results
          .dig("identity.authored_content", "details", "processing")
        assert_equal AuthoredContentDeletion::WAITING_STATUS, processing.fetch("status")
        early = ReconcileAuthoredContentDeletion.call(
          at: Time.iso8601(processing.fetch("next_recheck_at")) - 1.second
        )
        assert_predicate early, :success?, early.error
        assert_equal 0, early.value.fetch(:resumed)

        released = DataGovernance::ReleaseRetentionHold.call(
          hold: hold.value.fetch(:hold),
          actor:,
          reason: "The investigation completed."
        )
        assert_predicate released, :success?, released.error
        resumed = ReconcileAuthoredContentDeletion.call(
          at: Time.iso8601(processing.fetch("next_recheck_at")) + 1.second
        )
        assert_predicate resumed, :success?, resumed.error
        assert_equal 1, resumed.value.fetch(:resumed)
        resumed_processing = @user.reload.account_closure_results
          .dig("identity.authored_content", "details", "processing")
        assert_equal processing.fetch("request_key"), resumed_processing.fetch("request_key")
        assert_equal processing.fetch("upper_bounds"), resumed_processing.fetch("upper_bounds")

        completed = AuthoredContentDeletion.execute(deletion_intents.last)

        assert_equal "succeeded", completed.status
        assert_equal "authored_content_deleted", @user.reload.account_closure_outcome
        assert_predicate Community::Message.with_discarded.find(message.id), :soft_deleted?
        assert DataGovernance::ContentLifecycleRecord.exists?(
          target_type: "Community::Message",
          target_id: message.id
        )
      end

      test "an account level hold defers without scanning and resumes after release" do
        message = Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Account-held evidence"
        )
        actor = create_user
        hold = DataGovernance::PlaceRetentionHold.call(
          target: @user,
          actor:,
          reason: "Preserve all account evidence."
        )
        assert_predicate hold, :success?, hold.error
        close_with_content_deletion

        deferred = AuthoredContentDeletion.execute(deletion_intents.first)

        assert_equal "succeeded", deferred.status
        assert_equal 0, deferred.metadata.fetch("processed_records")
        assert_equal "legally_retained", @user.reload.account_closure_outcome
        refute_predicate Community::Message.find(message.id), :soft_deleted?
        processing = @user.account_closure_results
          .dig("identity.authored_content", "details", "processing")
        assert_equal AuthoredContentDeletion::WAITING_STATUS, processing.fetch("status")

        released = DataGovernance::ReleaseRetentionHold.call(
          hold: hold.value.fetch(:hold),
          actor:,
          reason: "The account hold is no longer required."
        )
        assert_predicate released, :success?, released.error
        resumed = ReconcileAuthoredContentDeletion.call(
          at: Time.iso8601(processing.fetch("next_recheck_at")) + 1.second
        )
        assert_predicate resumed, :success?, resumed.error
        assert_equal 1, resumed.value.fetch(:resumed)

        completed = AuthoredContentDeletion.execute(deletion_intents.last)

        assert_equal "succeeded", completed.status
        assert_equal "authored_content_deleted", @user.reload.account_closure_outcome
        assert_predicate Community::Message.with_discarded.find(message.id), :soft_deleted?
      end

      test "historical retained closures are rejoined to the durable deletion lifecycle" do
        message = Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Historically retained content"
        )
        closed = CloseAccount.call(
          user: @user,
          password: "password123",
          confirmation: "DELETE"
        )
        assert_predicate closed, :success?, closed.error
        results = @user.reload.account_closure_results.deep_dup
        contribution = results.fetch("identity.authored_content")
        contribution.fetch("details").merge!(
          "outcome" => "legally_retained",
          "deleted_records" => { "topics" => 0, "posts" => 0, "messages" => 0 }
        )
        contribution.fetch("details").delete("processing")
        @user.update!(
          account_closure_outcome: "legally_retained",
          account_closure_results: results
        )

        reconciled = ReconcileAuthoredContentDeletion.call

        assert_predicate reconciled, :success?, reconciled.error
        assert_equal 1, reconciled.value.fetch(:queued)
        processing = @user.reload.account_closure_results
          .dig("identity.authored_content", "details", "processing")
        assert_equal false, processing.fetch("repair_only")
        processed = AuthoredContentDeletion.execute(deletion_intents.last)
        assert_equal "succeeded", processed.status
        assert_predicate Community::Message.with_discarded.find(message.id), :soft_deleted?
      end

      test "reconciliation candidates use Arel predicates without widening closure gates" do
        Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Historical deletion candidate"
        )
        @user.update!(
          status: :deleted,
          account_closed_at: 1.day.ago,
          account_closure_outcome: "authored_content_deleted",
          account_closure_results: {
            "identity.authored_content" => {
              "details" => { "closure_mode" => "delete_content" }
            }
          }
        )

        retained_user = create_user
        Community::Message.create!(
          conversation: @conversation,
          user: retained_user,
          body: "Retained content is not a deletion candidate"
        )
        retained_user.update!(
          status: :deleted,
          account_closed_at: 1.day.ago,
          account_closure_outcome: "stable_anonymous_author",
          account_closure_results: {
            "identity.authored_content" => {
              "details" => { "closure_mode" => "retain_content" }
            }
          }
        )

        service = ReconcileAuthoredContentDeletion.new
        predicates = %i[
          missing_lifecycle_predicate
          active_authored_content_predicate
          topic_scrub_required_predicate
          opening_post_scrub_required_predicate
          profile_post_scrub_required_predicate
        ].map { |name| service.send(name) }

        predicates.each { |predicate| assert_kind_of Arel::Nodes::Node, predicate }
        assert_equal [ @user.id ],
                     service.send(:candidate_users)
                       .where(id: [ @user.id, retained_user.id ])
                       .pluck(:id)
      end

      test "historically redacted content is reconciled into a governed lifecycle" do
        message = Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Already redacted"
        )
        hold = DataGovernance::PlaceRetentionHold.call(
          target: message,
          actor: create_user,
          reason: "Historical evidence remains held while lifecycle metadata is repaired."
        )
        assert_predicate hold, :success?
        closed = CloseAccount.call(
          user: @user,
          password: "password123",
          confirmation: "DELETE"
        )
        assert_predicate closed, :success?
        historical_deleted_at = 10.days.ago.change(usec: 0)
        message.update_columns(body: "[deleted]", deleted_at: historical_deleted_at)
        results = @user.reload.account_closure_results.deep_dup
        details = results.fetch("identity.authored_content").fetch("details")
        details["outcome"] = "authored_content_deleted"
        details["deleted_records"] = { "topics" => 0, "posts" => 0, "messages" => 1 }
        @user.update!(
          account_closure_outcome: "authored_content_deleted",
          account_closure_results: results
        )

        reconciled = ReconcileAuthoredContentDeletion.call

        assert_predicate reconciled, :success?
        assert_equal 1, reconciled.value.fetch(:queued)
        intent = deletion_intents.first
        AuthoredContentDeletion.execute(intent)
        lifecycle = DataGovernance::ContentLifecycleRecord.find_by!(
          target_type: "Community::Message",
          target_id: message.id
        )
        assert_predicate lifecycle, :status_soft_deleted?
        assert_equal historical_deleted_at, lifecycle.soft_deleted_at
        assert_equal historical_deleted_at, message.reload.deleted_at
        assert_includes lifecycle.blocker_codes, "legal_hold"
        assert_equal "[deleted]", Community::Message.with_discarded.find(message.id).body
        assert_equal "authored_content_deleted", @user.reload.account_closure_outcome
        assert_equal 1,
                     @user.account_closure_results
                       .dig(
                         "identity.authored_content",
                         "details",
                         "lifecycle_repaired_records",
                         "messages"
                       )
      end

      test "account closure preserves shared topic containers and other authors replies" do
        suffix = SecureRandom.hex(5)
        category = Community::Category.create!(
          name: "Closure safety #{suffix}",
          slug: "closure-safety-#{suffix}"
        )
        section = Community::Section.create!(
          category:,
          name: "Closure safety",
          slug: "closure-safety-#{suffix}",
          position: 0
        )
        other = create_user
        topics = {
          mixed: create_owned_topic(section:, title: "Mixed discussion"),
          staff: create_owned_topic(section:, title: "Staff managed", pinned: true),
          announcement: create_owned_topic(
            section:,
            title: "Announcement",
            global_announcement: true
          ),
          commerce: create_owned_topic(section:, title: "Commerce managed"),
          locked: create_owned_topic(section:, title: "Locked discussion", locked: true)
        }
        owned_posts = topics.values.map do |topic|
          Community::Post.create!(
            topic:,
            user: @user,
            floor_number: 1,
            body: "Closing author body for #{topic.title}",
            status: "published"
          )
        end
        other_reply = Community::Post.create!(
          topic: topics.fetch(:mixed),
          user: other,
          floor_number: 2,
          body: "Another member must remain",
          status: "published"
        )
        owned_reply = Community::Post.create!(
          topic: topics.fetch(:mixed),
          user: @user,
          floor_number: 3,
          body: "Closing author's ordinary reply",
          status: "published"
        )
        owned_posts.first.edit_body!(
          "Edited opening body",
          editor: @user,
          reason: "Personal edit reason"
        )
        opening_attachment = Community::PostAttachment.create!(
          post: owned_posts.first,
          user: @user,
          filename: "personal-evidence.txt",
          content_type: "text/plain",
          byte_size: 12
        )
        attachment_upload = managed_upload(
          post: owned_posts.first,
          kind: "post_attachment",
          attachment: opening_attachment
        )
        inline_upload = managed_upload(
          post: owned_posts.first,
          kind: "inline_image"
        )
        staff_note = Community::TopicStaffNote.create!(
          topic: topics.fetch(:staff),
          author: other,
          body: "Staff evidence must remain"
        )
        product = Commerce::Product.create!(
          name: "Closure topic product",
          slug: "closure-topic-product-#{suffix}",
          product_type: "digital",
          status: "draft",
          price_cents: 0,
          currency: "USD",
          minimum_quantity: 1,
          forum_topic: topics.fetch(:commerce)
        )

        close_with_content_deletion
        after_commit_callbacks = []
        result = ActiveRecord.stub(
          :after_all_transactions_commit,
          ->(&callback) { after_commit_callbacks << callback }
        ) do
          AuthoredContentDeletion.execute(deletion_intents.first)
        end

        assert_equal "succeeded", result.status
        replacement = I18n.t("mcweb.identity.deleted_content_title", locale: @user.locale)
        topics.each_value do |topic|
          retained = Community::Topic.with_discarded.find(topic.id)
          refute_predicate retained, :soft_deleted?
          assert_equal replacement, retained.title
          refute DataGovernance::ContentLifecycleRecord.exists?(
            target_type: "Community::Topic",
            target_id: retained.id
          )
        end
        assert_predicate topics.fetch(:staff).reload, :pinned?
        assert_predicate topics.fetch(:announcement).reload, :global_announcement?
        assert_predicate topics.fetch(:locked).reload, :locked?
        assert_equal topics.fetch(:commerce).id, product.reload.forum_topic_id
        assert_equal "Staff evidence must remain", staff_note.reload.body
        assert_equal "Another member must remain", other_reply.reload.body
        refute_predicate other_reply, :soft_deleted?
        replacement_body = I18n.t(
          "mcweb.identity.deleted_content_body",
          locale: @user.locale
        )
        owned_posts.each do |post|
          retained = Community::Post.with_discarded.find(post.id)
          refute_predicate retained, :soft_deleted?
          assert_equal replacement_body, retained.body
          refute DataGovernance::ContentLifecycleRecord.exists?(
            target_type: "Community::Post",
            target_id: retained.id
          )
        end
        owned_posts.first.edits.each do |edit|
          assert_equal replacement_body, edit.body_before
          assert_equal replacement_body, edit.body_after
          assert_nil edit.reason
        end
        assert_nil opening_attachment.reload.forum_post_id
        assert_equal "cleanup_pending", attachment_upload.reload.status
        assert_nil attachment_upload.forum_post_id
        assert_equal opening_attachment.id, attachment_upload.forum_post_attachment_id
        assert_equal "cleanup_pending", inline_upload.reload.status
        assert_nil inline_upload.forum_post_id
        assert_enqueued_jobs 2, only: Maintenance::CleanupForumUploadsJob do
          after_commit_callbacks.each(&:call)
        end
        assert_predicate Community::Post.with_discarded.find(owned_reply.id), :soft_deleted?
        assert_equal 1, topics.fetch(:mixed).reload.replies_count
      end

      test "profile wall containers preserve other members comments while author text is removed" do
        wall_owner = create_user
        other = create_user
        shared_post = Community::ProfilePost.create!(
          profile_user: wall_owner,
          author: @user,
          body: "Closing author's shared wall text",
          status: "published"
        )
        retained_comment = Community::ProfilePostComment.create!(
          profile_post: shared_post,
          author: other,
          body: "Other member comment",
          status: "published"
        )
        other_post = Community::ProfilePost.create!(
          profile_user: wall_owner,
          author: other,
          body: "Other member wall text",
          status: "published"
        )
        closing_comment = Community::ProfilePostComment.create!(
          profile_post: other_post,
          author: @user,
          body: "Closing author's comment",
          status: "published"
        )

        close_with_content_deletion
        result = AuthoredContentDeletion.execute(deletion_intents.first)

        assert_equal "succeeded", result.status
        retained_post = Community::ProfilePost.with_discarded.find(shared_post.id)
        refute_predicate retained_post, :soft_deleted?
        assert_equal I18n.t("mcweb.identity.deleted_content_body", locale: @user.locale),
                     retained_post.body
        refute DataGovernance::ContentLifecycleRecord.exists?(
          target_type: "Community::ProfilePost",
          target_id: shared_post.id
        )
        assert_equal "Other member comment", retained_comment.reload.body
        refute_predicate retained_comment, :soft_deleted?
        assert_predicate Community::ProfilePostComment.with_discarded
          .find(closing_comment.id), :soft_deleted?
      end

      test "delayed deletion starts retention at execution time" do
        message = Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Delete when the durable batch executes"
        )
        close_with_content_deletion
        closed_at = @user.reload.account_closed_at
        execution_at = (closed_at + 3.days).change(usec: 0)

        travel_to(execution_at) do
          AuthoredContentDeletion.execute(deletion_intents.first)
        end

        lifecycle = DataGovernance::ContentLifecycleRecord.find_by!(
          target_type: "Community::Message",
          target_id: message.id
        )
        assert_equal execution_at, message.reload.deleted_at
        assert_equal execution_at, lifecycle.soft_deleted_at
      end

      test "account closure lifecycle cannot be restored and direct restoration is reconciled" do
        message = Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Closure deletion is final"
        )
        close_with_content_deletion
        AuthoredContentDeletion.execute(deletion_intents.first)
        lifecycle = DataGovernance::ContentLifecycleRecord.find_by!(
          target_type: "Community::Message",
          target_id: message.id
        )

        restore = DataGovernance::RestoreContent.call(
          record: lifecycle,
          actor: create_user,
          reason: "Attempt to bypass the closure request."
        )

        assert_predicate restore, :failure?
        assert_equal "account_closure_content_not_restorable", restore.code
        message.reload.restore!

        reconciled = ReconcileAuthoredContentDeletion.call

        assert_predicate reconciled, :success?
        assert_equal 1, reconciled.value.fetch(:queued)
        AuthoredContentDeletion.execute(deletion_intents.last)
        assert_predicate message.reload, :soft_deleted?
        assert_predicate lifecycle.reload, :status_soft_deleted?
      end

      test "completed closures reconcile legacy structural lifecycles and reattached uploads" do
        suffix = SecureRandom.hex(5)
        category = Community::Category.create!(
          name: "Legacy structural #{suffix}",
          slug: "legacy-structural-#{suffix}"
        )
        section = Community::Section.create!(
          category:,
          name: "Legacy structural",
          slug: "legacy-structural-#{suffix}",
          position: 0
        )
        topic = create_owned_topic(section:, title: "Legacy shared topic")
        opening_post = Community::Post.create!(
          topic:,
          user: @user,
          floor_number: 1,
          body: "Legacy opening body",
          status: "published"
        )
        wall_post = Community::ProfilePost.create!(
          profile_user: create_user,
          author: @user,
          body: "Legacy shared wall body",
          status: "published"
        )
        retained_comment = Community::ProfilePostComment.create!(
          profile_post: wall_post,
          author: create_user,
          body: "Retained wall reply",
          status: "published"
        )

        close_with_content_deletion
        AuthoredContentDeletion.execute(deletion_intents.first)
        topic_lifecycle = create_legacy_structural_lifecycle(topic.reload)
        post_lifecycle = create_legacy_structural_lifecycle(opening_post.reload)
        wall_lifecycle = create_legacy_structural_lifecycle(wall_post.reload)
        # Older releases could restore the container while leaving its label and
        # owner name in the lifecycle JSON. The reconciliation selector must
        # still find and scrub that snapshot even when the visible body and
        # lifecycle status otherwise look complete.
        wall_post.restore!
        wall_lifecycle.update!(
          status: "restored",
          restored_at: Time.current,
          restoration_reason: "legacy_restore_without_snapshot_scrub"
        )
        attachment = Community::PostAttachment.create!(
          post: opening_post,
          user: @user,
          filename: "late-personal.txt",
          content_type: "text/plain",
          byte_size: 8
        )
        upload = managed_upload(
          post: opening_post,
          kind: "post_attachment",
          attachment:
        )

        reconciled = ReconcileAuthoredContentDeletion.call

        assert_predicate reconciled, :success?, reconciled.error
        assert_equal 1, reconciled.value.fetch(:queued)
        after_commit_callbacks = []
        processed = ActiveRecord.stub(
          :after_all_transactions_commit,
          ->(&callback) { after_commit_callbacks << callback }
        ) do
          AuthoredContentDeletion.execute(deletion_intents.last)
        end

        assert_equal "succeeded", processed.status
        [ topic_lifecycle, post_lifecycle, wall_lifecycle ].each do |lifecycle|
          assert_predicate lifecycle.reload, :status_restored?
          assert_equal "account_closure_structural_container_preserved",
                       lifecycle.restoration_reason
          refute lifecycle.target_snapshot.key?("label")
        end
        refute_predicate topic.reload, :soft_deleted?
        refute_predicate opening_post.reload, :soft_deleted?
        refute_predicate wall_post.reload, :soft_deleted?
        assert_equal I18n.t("mcweb.identity.deleted_content_title", locale: @user.locale),
                     topic.title
        assert_equal I18n.t("mcweb.identity.deleted_content_body", locale: @user.locale),
                     opening_post.body
        assert_equal I18n.t("mcweb.identity.deleted_content_body", locale: @user.locale),
                     wall_post.body
        assert_equal "Retained wall reply", retained_comment.reload.body
        assert_nil attachment.reload.forum_post_id
        assert_equal "cleanup_pending", upload.reload.status
        assert_equal attachment.id, upload.forum_post_attachment_id
        assert_enqueued_jobs 1, only: Maintenance::CleanupForumUploadsJob do
          after_commit_callbacks.each(&:call)
        end
      end

      test "completed closures reconcile a legacy structural restoration reason" do
        wall_post = Community::ProfilePost.create!(
          profile_user: create_user,
          author: @user,
          body: "Legacy shared wall body",
          status: "published"
        )

        close_with_content_deletion
        AuthoredContentDeletion.execute(deletion_intents.first)
        lifecycle = create_legacy_structural_lifecycle(wall_post.reload)
        wall_post.restore!
        scrubbed_snapshot = DataGovernance::ContentRegistry.scrubbed_snapshot(
          lifecycle.target_snapshot,
          type: wall_post.class.base_class.name
        )
        lifecycle.update!(
          status: "restored",
          restored_at: Time.current,
          restoration_reason: "legacy_restore_without_snapshot_scrub",
          target_snapshot: scrubbed_snapshot
        )

        reconciled = ReconcileAuthoredContentDeletion.call

        assert_predicate reconciled, :success?, reconciled.error
        assert_equal 1, reconciled.value.fetch(:queued)
        processed = AuthoredContentDeletion.execute(deletion_intents.last)

        assert_equal "succeeded", processed.status
        assert_predicate lifecycle.reload, :status_restored?
        assert_equal AuthoredContentDeletion::STRUCTURAL_RESTORATION_REASON,
                     lifecycle.restoration_reason
        refute lifecycle.target_snapshot.key?("label")
        refute_predicate wall_post.reload, :soft_deleted?
      end

      test "automatic dead letter recovery becomes terminal manual attention" do
        Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Poison batch"
        )
        close_with_content_deletion
        intent = deletion_intents.first
        results = @user.reload.account_closure_results.deep_dup
        processing = results.dig("identity.authored_content", "details", "processing")
        processing["recovery_count"] = ReconcileAuthoredContentDeletion::MAX_AUTOMATIC_RECOVERIES
        @user.update!(account_closure_results: results)
        Operations::DurableEnqueueLedger.append!(
          intent:,
          event_type: "dead_lettered",
          error_code: "attempts_exhausted"
        )

        signals = []
        log_messages = []
        subscriber = ActiveSupport::Notifications.subscribe(
          "identity.account_closure_content.manual_attention"
        ) do |event|
          signals << event.payload
        end
        reconciled = Rails.logger.stub(:error, ->(message) { log_messages << message }) do
          ReconcileAuthoredContentDeletion.call
        end

        assert_predicate reconciled, :success?
        assert_equal 1, reconciled.value.fetch(:manual_attention)
        processing = @user.reload.account_closure_results
          .dig("identity.authored_content", "details", "processing")
        assert_equal AuthoredContentDeletion::MANUAL_ATTENTION_STATUS,
                     processing.fetch("status")
        assert_equal "manual_attention_required", @user.account_closure_outcome
        assert_equal 1, deletion_intents.count
        assert_equal 1, signals.size
        assert_equal @user.public_id, signals.first.fetch(:user_public_id)
        assert_equal intent.public_id, signals.first.fetch(:intent_public_id)
        assert_equal "attempts_exhausted", signals.first.fetch(:failure_code)
        assert_includes log_messages.join("\n"), @user.public_id
        assert_includes log_messages.join("\n"), intent.public_id
        refute_includes log_messages.join("\n"), @user.email
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      end

      test "manual attention survives a failing runtime notification subscriber" do
        Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Poison batch with a broken monitoring subscriber"
        )
        close_with_content_deletion
        intent = deletion_intents.first
        results = @user.reload.account_closure_results.deep_dup
        processing = results.dig("identity.authored_content", "details", "processing")
        processing["recovery_count"] = ReconcileAuthoredContentDeletion::MAX_AUTOMATIC_RECOVERIES
        @user.update!(account_closure_results: results)
        Operations::DurableEnqueueLedger.append!(
          intent:,
          event_type: "dead_lettered",
          error_code: "attempts_exhausted"
        )

        subscriber = ActiveSupport::Notifications.subscribe(
          "identity.account_closure_content.manual_attention"
        ) { raise "monitor unavailable" }
        reconciled = ReconcileAuthoredContentDeletion.call

        assert_predicate reconciled, :success?
        assert_equal 1, reconciled.value.fetch(:manual_attention)
        assert_equal "manual_attention_required", @user.reload.account_closure_outcome
        assert_equal AuthoredContentDeletion::MANUAL_ATTENTION_STATUS,
                     @user.account_closure_results
                       .dig("identity.authored_content", "details", "processing", "status")
        assert AuditLog.exists?(
          action: "identity.account_closure_content_manual_attention",
          resource_id: @user.id
        )
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      end

      test "a backed off low id request cannot monopolize dead letter recovery" do
        base_time = Time.current
        Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Low id request in backoff"
        )
        close_with_content_deletion
        low_intent = deletion_intents.first
        Operations::DurableEnqueueLedger.append!(
          intent: low_intent,
          event_type: "dead_lettered",
          error_code: "attempts_exhausted",
          occurred_at: base_time
        )
        ReconcileAuthoredContentDeletion.call(limit: 1, at: base_time)

        later_user = create_user
        later_conversation = Community::Conversation.create!(title: "Later recovery")
        Community::ConversationParticipant.create!(
          conversation: later_conversation,
          user: later_user
        )
        Community::Message.create!(
          conversation: later_conversation,
          user: later_user,
          body: "Higher id request is already due"
        )
        closed = CloseAccount.call(
          user: later_user,
          password: "password123",
          confirmation: "DELETE",
          closure_mode: "delete_content"
        )
        assert_predicate closed, :success?
        later_intents = Operations::DurableEnqueueIntent.where(
          handler_key: AuthoredContentDeletion::HANDLER_KEY,
          source_id: later_user.id
        ).order(:id)
        Operations::DurableEnqueueLedger.append!(
          intent: later_intents.first,
          event_type: "dead_lettered",
          error_code: "attempts_exhausted",
          occurred_at: base_time - 2.hours
        )

        recovered = ReconcileAuthoredContentDeletion.call(limit: 1, at: base_time)

        assert_predicate recovered, :success?
        assert_equal 1, recovered.value.fetch(:requeued)
        assert_equal 2, later_intents.reload.count
        assert_equal 1, deletion_intents.count
      end

      test "a dead lettered batch is durably requeued without resetting its cursor" do
        message = Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Recover after retries"
        )
        close_with_content_deletion
        first_intent = deletion_intents.first
        dead_lettered_at = Time.current
        Operations::DurableEnqueueLedger.append!(
          intent: first_intent,
          event_type: "dead_lettered",
          error_code: "attempts_exhausted",
          occurred_at: dead_lettered_at
        )

        backed_off = ReconcileAuthoredContentDeletion.call(at: dead_lettered_at)

        assert_predicate backed_off, :success?
        assert_equal 1, backed_off.value.fetch(:recovery_backoff)
        assert_equal AuthoredContentDeletion::RECOVERY_BACKOFF_STATUS,
                     @user.reload.account_closure_results
                       .dig("identity.authored_content", "details", "processing", "status")
        assert_equal 1, deletion_intents.count

        reconciled = ReconcileAuthoredContentDeletion.call(
          at: dead_lettered_at + 1.hour + 1.second
        )

        assert_predicate reconciled, :success?
        assert_equal 1, reconciled.value.fetch(:requeued)
        assert_equal 2, deletion_intents.count
        recovery_intent = deletion_intents.last
        assert_equal 2, recovery_intent.arguments.fetch("batch_number")

        processed = AuthoredContentDeletion.execute(recovery_intent)

        assert_equal "succeeded", processed.status
        assert_equal "authored_content_deleted", @user.reload.account_closure_outcome
        assert_equal 1, DataGovernance::ContentLifecycleRecord.where(
          target_type: "Community::Message",
          target_id: message.id
        ).count
        assert_equal 1,
                     @user.account_closure_results
                       .dig("identity.authored_content", "details", "processing", "recovery_count")
      end

      test "closure rolls back if its durable deletion intent cannot be admitted" do
        Community::Message.create!(
          conversation: @conversation,
          user: @user,
          body: "Must not orphan"
        )

        Operations::DurableEnqueueAdmission.stub(
          :record!,
          ->(**) { raise Operations::DurableEnqueueAdmission::Unavailable }
        ) do
          result = close_with_content_deletion

          assert_predicate result, :failure?
        end

        assert_predicate @user.reload, :active?
        assert_nil @user.account_closed_at
        assert_empty deletion_intents
      end

      private

      def create_owned_topic(section:, title:, **attributes)
        Community::Topic.create!(
          {
            public_id: "topic_#{SecureRandom.alphanumeric(16)}",
            section:,
            user: @user,
            title:,
            status: "published",
            last_posted_at: Time.current,
            last_post_user: @user,
            replies_count: 0
          }.merge(attributes)
        )
      end

      def close_with_content_deletion
        CloseAccount.call(
          user: @user,
          password: "password123",
          confirmation: "DELETE",
          closure_mode: "delete_content"
        )
      end

      def managed_upload(post:, kind:, attachment: nil)
        Community::Upload.create!(
          user: @user,
          public_id: Community::Upload.generate_public_id,
          kind:,
          status: "linked",
          scan_status: "clean",
          byte_size: 12,
          post:,
          post_attachment: attachment
        )
      end

      def create_legacy_structural_lifecycle(target)
        at = 1.day.ago.change(usec: 0)
        snapshot = DataGovernance::ContentRegistry.snapshot(target)
        target.soft_delete!(at:)
        DataGovernance::ContentLifecycleRecord.create!(
          target_type: target.class.base_class.name,
          target_id: target.id,
          status: "soft_deleted",
          deleted_by: @user,
          soft_deleted_at: at,
          purge_after: at + 30.days,
          deletion_reason: "account_closure_delete_content",
          target_snapshot: snapshot
        )
      end

      def deletion_intents
        Operations::DurableEnqueueIntent
          .where(
            handler_key: AuthoredContentDeletion::HANDLER_KEY,
            source_id: @user.id
          )
          .order(:id)
      end
    end
  end
end
