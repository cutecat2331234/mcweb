# frozen_string_literal: true

require "test_helper"

module Community
  class ModerationWorkbenchTest < ActiveSupport::TestCase
    setup do
      suffix = SecureRandom.hex(4)
      category = Community::Category.create!(
        name: "Workbench #{suffix}",
        slug: "workbench-#{suffix}"
      )
      @section = Community::Section.create!(
        category: category,
        name: "Workbench section",
        slug: "workbench-section-#{suffix}",
        position: 0
      )
      @other_section = Community::Section.create!(
        category: category,
        name: "Other section",
        slug: "workbench-other-#{suffix}",
        position: 1
      )
      @moderator = create_user(username: "workbench_mod_#{suffix}")
      @other_moderator = create_user(username: "workbench_mod2_#{suffix}")
      @author = create_user(username: "workbench_author_#{suffix}")
      Community::SectionModerator.create!(section: @section, user: @moderator)
      Community::SectionModerator.create!(section: @section, user: @other_moderator)
      grant_permission(@other_moderator, "admin.access")
      grant_permission(@other_moderator, "forum.users.warn")
    end

    test "sync cases aggregates pending content reports spam quarantine and user risk" do
      topic, opening = create_topic_and_post(
        section: @section,
        status: "pending_approval",
        topic_status: "hidden",
        floor_number: 1
      )
      reply = Community::Post.create!(
        topic: topic,
        user: @author,
        floor_number: 2,
        body: "A pending reply",
        status: "pending_approval"
      )
      report = Community::Report.create!(
        reporter: create_user,
        reportable: opening,
        reason_code: "offensive",
        reason: "This content needs review."
      )
      spam = Community::Report.create!(
        reporter: create_user,
        reportable: reply,
        reason_code: "spam",
        reason: "Repeated promotional links."
      )
      upload = create_quarantined_upload
      warning = Community::UserWarning.create!(
        user: @author,
        issuer: @moderator,
        reason: "Repeated rule violations.",
        points: 6,
        expires_at: 2.days.from_now
      )
      mute = Community::Mute.create!(
        user: @author,
        created_by: @moderator,
        section: @section,
        reason: "Cooling off period.",
        expires_at: 1.day.from_now
      )
      banned = create_user
      banned.ban!(reason: "Account abuse", expires_at: 3.days.from_now)

      result = Community::ModerationWorkbench::SyncCases.call

      assert_predicate result, :success?, result.error
      assert_case_kind(opening, "pending_topic")
      assert_case_kind(reply, "pending_post")
      assert_case_kind(report, "report")
      assert_case_kind(spam, "spam_hit")
      assert_case_kind(upload, "quarantined_attachment")
      assert_case_kind(warning, "user_risk")
      assert_case_kind(mute, "user_risk")
      assert_case_kind(banned, "user_risk")
      assert_equal "critical", moderation_case_for(upload).risk_level
      assert_equal "high", moderation_case_for(spam).priority
    end

    test "evidence permissions crop attachment warning mute and ban families independently" do
      upload = create_quarantined_upload
      warning_reason = "W" * 12_001
      mute_reason = "M" * 12_001
      ban_reason = "B" * 12_001
      warning = Community::UserWarning.create!(
        user: @author,
        issuer: @moderator,
        reason: warning_reason,
        points: 2
      )
      mute = Community::Mute.create!(
        user: @author,
        created_by: @moderator,
        reason: mute_reason,
        expires_at: 1.day.from_now
      )
      banned = create_user
      banned.ban!(reason: ban_reason, expires_at: 1.day.from_now)
      Community::ModerationWorkbench::SyncCases.call

      attachment_reader = create_user
      grant_permission(attachment_reader, "forum.attachments.security.read")
      attachment_detail = detail_for(attachment_reader, moderation_case_for(upload))
      assert_equal false, attachment_detail.dig(:evidence, :restricted)
      assert_equal "attachment", attachment_detail.dig(:evidence, :type)
      assert_empty attachment_detail.fetch(:available_actions)
      assert_empty attachment_detail.fetch(:assignable_staff)
      read_only_claim = manage(
        moderation_case_for(upload),
        actor: attachment_reader,
        action: "claim"
      )
      assert_predicate read_only_claim, :failure?
      assert_equal "moderation_case_forbidden", read_only_claim.error

      release_only = create_user
      grant_permission(release_only, "forum.attachments.security.release")
      refute Community::ModerationWorkbench::Policy.new(release_only)
        .visible?(moderation_case_for(upload))

      warning_reader = create_user
      grant_permission(warning_reader, "forum.users.warn")
      warning_detail = detail_for(warning_reader, moderation_case_for(warning))
      assert_equal false, warning_detail.dig(:evidence, :restricted)
      assert_equal "warning", warning_detail.dig(:evidence, :type)
      assert_equal true, warning_detail.dig(:evidence, :cropped)
      assert_equal warning_reason.first(12_000), warning_detail.dig(:evidence, :reason)
      mute_case = moderation_case_for(mute)
      refute Community::ModerationWorkbench::Policy.new(warning_reader).visible?(mute_case)

      mute_reader = create_user
      grant_permission(mute_reader, "forum.users.mute")
      mute_detail = detail_for(mute_reader, moderation_case_for(mute))
      assert_equal false, mute_detail.dig(:evidence, :restricted)
      assert_equal "mute", mute_detail.dig(:evidence, :type)
      assert_equal true, mute_detail.dig(:evidence, :cropped)
      assert_equal mute_reason.first(12_000), mute_detail.dig(:evidence, :reason)
      refute Community::ModerationWorkbench::Policy.new(mute_reader)
        .visible?(moderation_case_for(warning))

      refute Community::ModerationWorkbench::Policy.new(warning_reader)
        .evidence_visible?(moderation_case_for(banned))
      owner = create_user(account_type: "owner")
      ban_detail = detail_for(owner, moderation_case_for(banned))
      assert_equal false, ban_detail.dig(:evidence, :restricted)
      assert_equal "ban", ban_detail.dig(:evidence, :type)
      assert_equal true, ban_detail.dig(:evidence, :cropped)
      assert_equal ban_reason.first(12_000), ban_detail.dig(:evidence, :reason)
      filter_options = Community::ModerationWorkbench::Queue
        .new(actor: owner)
        .filter_options
      assert_includes filter_options.fetch(:sections).pluck(:id), @other_section.id
      assert_includes filter_options.fetch(:move_sections).pluck(:id), @other_section.id
    end

    test "manage case claims assigns and appends an immutable note with optimistic locking" do
      _, post = create_topic_and_post
      moderation_case = create_case(post)

      claim = manage(moderation_case, actor: @moderator, action: "claim")
      assert_predicate claim, :success?, claim.error
      claimed = claim.value.fetch(:moderation_case)
      assert_equal "claimed", claimed.status
      assert_equal @moderator.id, claimed.assignee_id
      assert AuditLog
        .for_resource(moderation_case)
        .by_action("admin.forum_moderation_case_claim")
        .exists?

      stale = manage(
        moderation_case,
        actor: @moderator,
        action: "note",
        lock_version: 0,
        body: "Stale note"
      )
      assert_predicate stale, :failure?
      assert_equal "moderation_case_conflict", stale.error
      assert_empty moderation_case.notes

      assign = manage(
        claimed,
        actor: @moderator,
        action: "assign",
        assignee_id: @other_moderator.id
      )
      assert_predicate assign, :success?, assign.error
      assigned = assign.value.fetch(:moderation_case)
      assert_equal @other_moderator.id, assigned.assignee_id

      unassign = manage(
        assigned,
        actor: @moderator,
        action: "assign",
        assignee_id: nil
      )
      assert_predicate unassign, :success?, unassign.error
      assigned = unassign.value.fetch(:moderation_case)
      assert_equal "open", assigned.status
      assert_nil assigned.assignee_id

      note = manage(
        assigned,
        actor: @moderator,
        action: "note",
        body: "Escalated after reviewing the evidence."
      )
      assert_predicate note, :success?, note.error
      assert_equal "Escalated after reviewing the evidence.", note.value.fetch(:note).body
      refute note.value.fetch(:note).update(body: "rewritten")
      refute note.value.fetch(:note).destroy
    end

    test "manage case rolls back assignment and note when immutable audit persistence fails" do
      _, post = create_topic_and_post
      moderation_case = create_case(post)

      assert_raises ActiveRecord::StatementInvalid do
        Administration::AuditLogger.stub(
          :call,
          ->(**) { raise ActiveRecord::StatementInvalid, "audit unavailable" }
        ) do
          manage(moderation_case, actor: @moderator, action: "claim")
        end
      end
      moderation_case.reload
      assert_equal "open", moderation_case.status
      assert_nil moderation_case.assignee_id

      assert_raises ActiveRecord::StatementInvalid do
        Administration::AuditLogger.stub(
          :call,
          ->(**) { raise ActiveRecord::StatementInvalid, "audit unavailable" }
        ) do
          manage(
            moderation_case,
            actor: @moderator,
            action: "note",
            body: "Must be rolled back"
          )
        end
      end
      assert_empty moderation_case.reload.notes
    end

    test "action authorization binds reason attributes cases and live state for five minutes" do
      _, post = create_topic_and_post
      moderation_case = create_case(post)
      request_id = SecureRandom.uuid
      issued = authorize(
        actor: @moderator,
        action: "resolve_case",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: "Reviewed and resolved.",
        attributes: { duration_days: 2 }
      )
      assert_predicate issued, :success?, issued.error
      payload = issued.value
      assert_match(
        /\ACONFIRM RESOLVE_CASE [0-9A-F]{8} [0-9A-F]{8}\z/,
        payload.fetch(:typed_confirmation)
      )
      assert_equal true, payload.dig(:preview, 0, :eligible)

      state = action_state(@moderator, "resolve_case", [ moderation_case ], duration_days: 2)
      assert Community::ModerationWorkbench::ActionAuthorization.valid?(
        payload.fetch(:authorization_token),
        actor: @moderator,
        action: "resolve_case",
        moderation_cases: [ moderation_case ],
        state: state,
        attributes: { duration_days: 2 },
        request_id: request_id,
        reason: "Reviewed and resolved."
      )
      refute Community::ModerationWorkbench::ActionAuthorization.valid?(
        payload.fetch(:authorization_token),
        actor: @moderator,
        action: "resolve_case",
        moderation_cases: [ moderation_case ],
        state: state,
        attributes: { duration_days: 3 },
        request_id: request_id,
        reason: "Reviewed and resolved."
      )
      refute Community::ModerationWorkbench::ActionAuthorization.valid?(
        payload.fetch(:authorization_token),
        actor: @moderator,
        action: "resolve_case",
        moderation_cases: [ moderation_case ],
        state: state,
        attributes: { duration_days: 2 },
        request_id: request_id,
        reason: "A changed reason."
      )

      moderation_case.update!(priority: "high")
      changed_state = action_state(
        @moderator,
        "resolve_case",
        [ moderation_case.reload ],
        duration_days: 2
      )
      refute Community::ModerationWorkbench::ActionAuthorization.valid?(
        payload.fetch(:authorization_token),
        actor: @moderator,
        action: "resolve_case",
        moderation_cases: [ moderation_case ],
        state: changed_state,
        attributes: { duration_days: 2 },
        request_id: request_id,
        reason: "Reviewed and resolved."
      )

      travel 6.minutes do
        refute Community::ModerationWorkbench::ActionAuthorization.valid?(
          payload.fetch(:authorization_token),
          actor: @moderator,
          action: "resolve_case",
          moderation_cases: [ moderation_case ],
          state: changed_state,
          attributes: { duration_days: 2 },
          request_id: request_id,
          reason: "Reviewed and resolved."
        )
      end
    end

    test "report visibility and authorization follow the reportable live section" do
      topic, post = create_topic_and_post
      report = Community::Report.create!(
        reporter: create_user,
        reportable: post,
        reason_code: "offensive",
        reason: "This report must follow the content into its current section."
      )
      Community::ModerationWorkbench::SyncCases.call
      moderation_case = moderation_case_for(report)
      request_id = SecureRandom.uuid
      reason = "Dismiss only while the report remains in my moderated section."
      issued = authorize(
        actor: @moderator,
        action: "dismiss_report",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: reason
      )
      assert_predicate issued, :success?, issued.error

      topic.update!(section: @other_section)

      policy = Community::ModerationWorkbench::Policy.new(@moderator)
      refute policy.visible?(moderation_case)
      refute Community::ModerationWorkbench::Queue
        .new(actor: @moderator)
        .relation
        .exists?(id: moderation_case.id)
      assert_predicate Community::ModerationWorkbench::CaseDetail.call(
        actor: @moderator,
        moderation_case: moderation_case
      ), :failure?

      executed = execute(
        actor: @moderator,
        action: "dismiss_report",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: reason,
        token: issued.value.fetch(:authorization_token),
        confirmation: issued.value.fetch(:typed_confirmation)
      )
      assert_predicate executed, :failure?
      assert_equal "moderation_authorization_invalid", executed.error
      assert_equal "pending", report.reload.status
      assert_equal "open", moderation_case.reload.status
    end

    test "execute action approves and rejects pending posts" do
      _, approval_post = create_topic_and_post(
        status: "pending_approval",
        topic_status: "hidden"
      )
      approval_case = create_case(approval_post)
      approved = authorize_and_execute(
        actor: @moderator,
        action: "approve",
        cases: [ approval_case ],
        reason: "Content follows the section rules."
      )
      assert_predicate approved, :success?, approved.error
      assert_equal "published", approval_post.reload.status
      assert_equal "actioned", approval_case.reload.status

      topic, _opening = create_topic_and_post
      rejection_post = Community::Post.create!(
        topic: topic,
        user: @author,
        floor_number: 2,
        body: "Pending reply to reject",
        status: "pending_approval"
      )
      rejection_case = create_case(rejection_post, source_kind: "pending_post")
      rejected = authorize_and_execute(
        actor: @moderator,
        action: "reject",
        cases: [ rejection_case ],
        reason: "The reply is unrelated to the topic."
      )
      assert_predicate rejected, :success?, rejected.error
      assert_equal "hidden", rejection_post.reload.status
      assert_equal "actioned", rejection_case.reload.status
    end

    test "execute action resolves and dismisses reports" do
      _, post = create_topic_and_post
      acted_report = create_report(post)
      acted_case = create_case(
        acted_report,
        source_kind: "report",
        target_user: post.user
      )
      acted = authorize_and_execute(
        actor: @moderator,
        action: "resolve_report",
        cases: [ acted_case ],
        reason: "The report is valid."
      )
      assert_predicate acted, :success?, acted.error
      assert_equal "actioned", acted_report.reload.status
      assert_equal "actioned", acted_case.reload.status

      _, second_post = create_topic_and_post
      dismissed_report = create_report(second_post)
      dismissed_case = create_case(
        dismissed_report,
        source_kind: "report",
        target_user: second_post.user
      )
      dismissed = authorize_and_execute(
        actor: @moderator,
        action: "dismiss_report",
        cases: [ dismissed_case ],
        reason: "The report is not substantiated."
      )
      assert_predicate dismissed, :success?, dismissed.error
      assert_equal "dismissed", dismissed_report.reload.status
      assert_equal "dismissed", dismissed_case.reload.status
    end

    test "bulk report dispositions mutate a shared reportable only once" do
      _, post = create_topic_and_post
      first_report = create_report(post)
      second_report = create_report(post)
      cases = [ first_report, second_report ].map do |report|
        create_case(report, source_kind: "report", target_user: post.user)
      end

      result = authorize_and_execute(
        actor: @moderator,
        action: "resolve_report",
        cases: cases,
        reason: "Resolve both reports while hiding their shared target only once."
      )

      assert_predicate result, :success?, result.error
      assert_equal [ "success" ], result.value.fetch(:results).pluck(:status).uniq
      assert_equal 1, result.value.fetch(:results).count { |item| item[:shared_target] }
      assert_equal [ "actioned" ], [ first_report.reload.status, second_report.reload.status ].uniq
      assert_equal [ "actioned" ], cases.map { |item| item.reload.status }.uniq
    end

    test "bulk report dismissals preserve a shared hide without durable provenance" do
      _, post = create_topic_and_post(status: "hidden")
      reports = [ create_report(post), create_report(post) ]
      cases = reports.map do |report|
        create_case(report, source_kind: "report", target_user: post.user)
      end

      result = authorize_and_execute(
        actor: @moderator,
        action: "dismiss_report",
        cases: cases,
        reason: "Dismiss both reports without reopening content hidden by another path."
      )

      assert_predicate result, :success?, result.error
      assert_equal [ "dismissed" ], reports.map { |item| item.reload.status }.uniq
      assert_equal "hidden", post.reload.status
      assert_equal 1, result.value.fetch(:results).count { |item| item[:shared_target] }
    end

    test "execute action warns mutes and permits bans only for account owners" do
      target = create_user
      warning_source = Community::UserWarning.create!(
        user: target,
        issuer: @other_moderator,
        reason: "Existing warning event.",
        points: 1,
        expires_at: 5.days.from_now
      )
      warning_case = create_case(
        warning_source,
        source_kind: "user_risk",
        section: nil,
        target_user: target
      )
      grant_permission(@moderator, "forum.users.warn")
      warned = authorize_and_execute(
        actor: @moderator,
        action: "warn_user",
        cases: [ warning_case ],
        reason: "Repeated disruptive behavior.",
        attributes: { points: 3, expire_days: 30 }
      )
      assert_predicate warned, :success?, warned.error
      assert_equal 2, Community::UserWarning.where(user: target).count
      assert_equal 3, Community::UserWarning.where(user: target).recent.first.points
      assert_equal "open", warning_case.reload.status

      mute_target = create_user
      mute_source = Community::Mute.create!(
        user: mute_target,
        created_by: @other_moderator,
        reason: "Existing mute event.",
        expires_at: 5.days.from_now
      )
      mute_case = create_case(
        mute_source,
        source_kind: "user_risk",
        section: nil,
        target_user: mute_target
      )
      grant_permission(@moderator, "forum.users.mute")
      muted = authorize_and_execute(
        actor: @moderator,
        action: "mute_user",
        cases: [ mute_case ],
        reason: "Temporary cooling off period.",
        attributes: { duration_days: 2 }
      )
      assert_predicate muted, :success?, muted.error
      assert Community::Mute.active.where(user: mute_target).exists?

      non_owner_plan = Community::ModerationWorkbench::ActionPlan.new(
        actor: @moderator,
        action: "ban_user",
        moderation_cases: [ mute_case ],
        attributes: { duration_days: 5 }
      )
      refute_predicate non_owner_plan, :any_eligible?
      assert_equal "moderation_action_not_available",
                   non_owner_plan.preview.first.fetch(:message)

      owner = create_user(account_type: "owner")
      ban_target = create_user
      ban_case = create_case(ban_target, source_kind: "user_risk", target_user: ban_target)
      banned = authorize_and_execute(
        actor: owner,
        action: "ban_user",
        cases: [ ban_case ],
        reason: "Confirmed account abuse.",
        attributes: { duration_days: 7 }
      )
      assert_predicate banned, :success?, banned.error
      assert_predicate ban_target.reload, :banned?
      assert_in_delta 7.days.from_now.to_f, ban_target.ban_expires_at.to_f, 5
    end

    test "bulk user sanctions deduplicate a shared target account" do
      target = create_user
      warning = Community::UserWarning.create!(
        user: target,
        issuer: @other_moderator,
        reason: "Existing warning event.",
        points: 1,
        expires_at: 5.days.from_now
      )
      mute = Community::Mute.create!(
        user: target,
        created_by: @other_moderator,
        reason: "Existing mute event.",
        expires_at: 5.days.from_now
      )
      cases = [
        create_case(warning, source_kind: "user_risk", section: nil, target_user: target),
        create_case(mute, source_kind: "user_risk", section: nil, target_user: target)
      ]
      grant_permission(@moderator, "forum.users.warn")
      grant_permission(@moderator, "forum.users.mute")
      before_count = Community::UserWarning.where(user: target).count

      result = authorize_and_execute(
        actor: @moderator,
        action: "warn_user",
        cases: cases,
        reason: "Record one sanction for the shared account behind both risk events.",
        attributes: { points: 2, expire_days: 30 }
      )

      assert_predicate result, :success?, result.error
      assert_equal before_count + 1, Community::UserWarning.where(user: target).count
      assert_equal 1, result.value.fetch(:results).count { |item| item[:shared_target] }
    end

    test "execute action replays an identical request and rejects changed request reuse" do
      _, post = create_topic_and_post
      moderation_case = create_case(post)
      request_id = SecureRandom.uuid
      first = authorize_and_execute(
        actor: @moderator,
        action: "resolve_case",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: "Resolution is complete."
      )
      assert_predicate first, :success?, first.error
      operation_id = first.value.fetch(:operation_id)

      replay = execute(
        actor: @moderator,
        action: "resolve_case",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: "Resolution is complete.",
        token: "not needed for replay",
        confirmation: "not needed for replay"
      )
      assert_predicate replay, :success?, replay.error
      assert_equal true, replay.value.fetch(:replayed)
      assert_equal operation_id, replay.value.fetch(:operation_id)
      assert_equal 1, Community::ModerationOperation.where(request_id: request_id).count

      reused = execute(
        actor: @moderator,
        action: "resolve_case",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: "Changed request body.",
        token: "not needed",
        confirmation: "not needed"
      )
      assert_predicate reused, :failure?
      assert_equal "moderation_request_id_reused", reused.error
    end

    test "execute action rejects expired or state changed authorizations" do
      _, post = create_topic_and_post
      moderation_case = create_case(post)
      request_id = SecureRandom.uuid
      issued = authorize(
        actor: @moderator,
        action: "resolve_case",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: "Reviewed before execution."
      )

      moderation_case.update!(priority: "critical")
      changed = execute(
        actor: @moderator,
        action: "resolve_case",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: "Reviewed before execution.",
        token: issued.value.fetch(:authorization_token),
        confirmation: issued.value.fetch(:typed_confirmation)
      )
      assert_predicate changed, :failure?
      assert_equal "moderation_authorization_invalid", changed.error
      assert_equal "open", moderation_case.reload.status

      second_request = SecureRandom.uuid
      second = authorize(
        actor: @moderator,
        action: "resolve_case",
        cases: [ moderation_case ],
        request_id: second_request,
        reason: "This authorization will expire."
      )
      expired = nil
      travel 6.minutes do
        expired = execute(
          actor: @moderator,
          action: "resolve_case",
          cases: [ moderation_case ],
          request_id: second_request,
          reason: "This authorization will expire.",
          token: second.value.fetch(:authorization_token),
          confirmation: second.value.fetch(:typed_confirmation)
        )
      end
      assert_predicate expired, :failure?
      assert_equal "moderation_authorization_invalid", expired.error
      assert_equal "open", moderation_case.reload.status
    end

    test "user sanctions bind the target account state into authorization" do
      owner = create_user(account_type: "owner")
      target = create_user
      _, post = create_topic_and_post(user: target)
      moderation_case = create_case(post, target_user: target)
      request_id = SecureRandom.uuid
      reason = "Ban the reviewed account for confirmed abuse."
      issued = authorize(
        actor: owner,
        action: "ban_user",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: reason,
        attributes: { duration_days: 7 }
      )
      assert_predicate issued, :success?, issued.error

      target.update!(account_type: "owner")

      result = execute(
        actor: owner,
        action: "ban_user",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: reason,
        attributes: { duration_days: 7 },
        token: issued.value.fetch(:authorization_token),
        confirmation: issued.value.fetch(:typed_confirmation)
      )
      assert_predicate result, :failure?
      assert_equal "moderation_authorization_invalid", result.error
      assert_equal "active", target.reload.status
      assert_equal "open", moderation_case.reload.status
    end

    test "execute action rolls back disposition and operation when immutable audit fails" do
      _, post = create_topic_and_post
      moderation_case = create_case(post)
      request_id = SecureRandom.uuid
      issued = authorize(
        actor: @moderator,
        action: "resolve_case",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: "Audit must be durable."
      )

      result = Administration::AuditLogger.stub(
        :call,
        ->(**) { raise ActiveRecord::StatementInvalid, "audit unavailable" }
      ) do
        execute(
          actor: @moderator,
          action: "resolve_case",
          cases: [ moderation_case ],
          request_id: request_id,
          reason: "Audit must be durable.",
          token: issued.value.fetch(:authorization_token),
          confirmation: issued.value.fetch(:typed_confirmation)
        )
      end

      assert_predicate result, :failure?
      assert_equal "moderation_action_transaction_failed", result.error
      assert_equal "open", moderation_case.reload.status
      refute Community::ModerationOperation.exists?(request_id: request_id)
      assert_equal "failed", result.value.fetch(:results).first.fetch(:status)
    end

    test "domain events flush after the operation commits and disappear on rollback" do
      _, post = create_topic_and_post(
        status: "pending_approval",
        topic_status: "hidden"
      )
      moderation_case = create_case(post)
      request_id = SecureRandom.uuid
      observed_commits = []
      subscriber = Mcweb::Events.subscribe("forum.post.approved") do
        observed_commits << Community::ModerationOperation.exists?(request_id: request_id)
      end

      successful = authorize_and_execute(
        actor: @moderator,
        action: "approve",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: "Approve this content and publish its event only after commit."
      )
      assert_predicate successful, :success?, successful.error
      assert_equal [ true ], observed_commits

      _, rollback_post = create_topic_and_post(
        status: "pending_approval",
        topic_status: "hidden"
      )
      rollback_case = create_case(rollback_post)
      rollback_request_id = SecureRandom.uuid
      issued = authorize(
        actor: @moderator,
        action: "approve",
        cases: [ rollback_case ],
        request_id: rollback_request_id,
        reason: "This approval must not publish when its audit rolls back."
      )
      rolled_back = Administration::AuditLogger.stub(
        :call,
        ->(**) { raise ActiveRecord::StatementInvalid, "audit unavailable" }
      ) do
        execute(
          actor: @moderator,
          action: "approve",
          cases: [ rollback_case ],
          request_id: rollback_request_id,
          reason: "This approval must not publish when its audit rolls back.",
          token: issued.value.fetch(:authorization_token),
          confirmation: issued.value.fetch(:typed_confirmation)
        )
      end

      assert_predicate rolled_back, :failure?
      assert_equal [ true ], observed_commits
      assert_equal "pending_approval", rollback_post.reload.status
    ensure
      Mcweb::Events.unsubscribe(subscriber) if subscriber
    end

    test "bulk execution records eligible successes and ineligible items as skipped" do
      _, visible_post = create_topic_and_post
      visible_case = create_case(visible_post)
      _, hidden_post = create_topic_and_post(section: @other_section)
      hidden_case = create_case(hidden_post, section: @other_section)
      request_id = SecureRandom.uuid

      result = authorize_and_execute(
        actor: @moderator,
        action: "resolve_case",
        cases: [ visible_case, hidden_case ],
        request_id: request_id,
        reason: "Close all cases visible to this moderation scope."
      )

      assert_predicate result, :success?, result.error
      by_id = result.value.fetch(:results).index_by { |item| item.fetch(:case_id) }
      assert_equal "success", by_id.fetch(visible_case.id).fetch(:status)
      assert_equal "skipped", by_id.fetch(hidden_case.id).fetch(:status)
      assert_equal "moderation_case_forbidden",
                   by_id.fetch(hidden_case.id).fetch(:message)
      assert_equal "resolved", visible_case.reload.status
      assert_equal "open", hidden_case.reload.status
    end

    test "execute action moves and deletes content and closes attachment dispositions" do
      owner = create_user(account_type: "owner")
      topic, opening = create_topic_and_post
      move_case = create_case(opening)

      moved = authorize_and_execute(
        actor: owner,
        action: "move_topic",
        cases: [ move_case ],
        reason: "Move this reviewed topic into the correct destination section.",
        attributes: { section_id: @other_section.id }
      )
      assert_predicate moved, :success?, moved.error
      assert_equal @other_section.id, topic.reload.forum_section_id
      assert_equal "open", move_case.reload.status

      reply = Community::Post.create!(
        topic: topic,
        user: @author,
        floor_number: 2,
        body: "Reply selected for soft deletion.",
        status: "published"
      )
      delete_case = create_case(reply, source_kind: "pending_post", section: @other_section)
      deleted = authorize_and_execute(
        actor: owner,
        action: "delete_content",
        cases: [ delete_case ],
        reason: "Remove the confirmed policy-violating reply from public view."
      )
      assert_predicate deleted, :success?, deleted.error
      assert_not_nil Community::Post.with_discarded.find(reply.id).deleted_at
      assert_equal "actioned", delete_case.reload.status

      release_upload = create_quarantined_upload
      release_case = create_case(
        release_upload,
        source_kind: "quarantined_attachment",
        section: nil
      )
      release_result = nil
      Community::ReleaseQuarantinedUpload.stub(
        :call,
        ->(**) { ServiceResult.success(upload: release_upload) }
      ) do
        release_result = authorize_and_execute(
          actor: owner,
          action: "release_attachment",
          cases: [ release_case ],
          reason: "Verified false positive after independent attachment review."
        )
      end
      assert_predicate release_result, :success?, release_result.error
      assert_equal "actioned", release_case.reload.status

      delete_upload = create_quarantined_upload
      attachment_case = create_case(
        delete_upload,
        source_kind: "quarantined_attachment",
        section: nil
      )
      assert_enqueued_jobs 1, only: Maintenance::CleanupForumUploadsJob do
        attachment_result = authorize_and_execute(
          actor: owner,
          action: "delete_attachment",
          cases: [ attachment_case ],
          reason: "Permanently remove the quarantined unsafe attachment."
        )
        assert_predicate attachment_result, :success?, attachment_result.error
      end
      assert_predicate delete_upload.reload, :status_cleanup_pending?
      assert_equal "actioned", attachment_case.reload.status
    end

    test "execute action bounds hierarchy lock retries and reports a conflict" do
      owner = create_user(account_type: "owner")
      topic, opening = create_topic_and_post
      moderation_case = create_case(opening)
      request_id = SecureRandom.uuid
      reason = "Move this reviewed topic into the correct destination section."
      attributes = { section_id: @other_section.id }
      issued = authorize(
        actor: owner,
        action: "move_topic",
        cases: [ moderation_case ],
        request_id: request_id,
        reason: reason,
        attributes: attributes
      )
      assert_predicate issued, :success?, issued.error

      attempts = 0
      result = Community::SectionHierarchyLock.stub(
        :lock_topics!,
        lambda do |*, **|
          attempts += 1
          raise ActiveRecord::Deadlocked, "simulated hierarchy lock deadlock"
        end
      ) do
        execute(
          actor: owner,
          action: "move_topic",
          cases: [ moderation_case ],
          request_id: request_id,
          reason: reason,
          attributes: attributes,
          token: issued.value.fetch(:authorization_token),
          confirmation: issued.value.fetch(:typed_confirmation)
        )
      end

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.moderation_action_conflict"), result.error
      assert_equal 3, attempts
      assert_equal @section.id, topic.reload.forum_section_id
      assert_equal "open", moderation_case.reload.status
      assert_not Community::ModerationOperation.exists?(request_id: request_id)
    end

    test "section moderators retain safe historical access after content deletion" do
      _, post = create_topic_and_post
      moderation_case = create_case(post)

      deleted = authorize_and_execute(
        actor: @moderator,
        action: "delete_content",
        cases: [ moderation_case ],
        reason: "Remove the confirmed violation while preserving its audit history."
      )

      assert_predicate deleted, :success?, deleted.error
      assert_not_nil Community::Post.with_discarded.find(post.id).deleted_at
      policy = Community::ModerationWorkbench::Policy.new(@moderator)
      assert policy.visible?(moderation_case.reload)
      assert Community::ModerationWorkbench::Queue
        .new(actor: @moderator, filters: { status: "actioned" })
        .relation
        .exists?(id: moderation_case.id)
      detail = Community::ModerationWorkbench::CaseDetail.call(
        actor: @moderator,
        moderation_case: moderation_case
      )
      assert_predicate detail, :success?, detail.error
      assert_equal true, detail.value.dig(:evidence, :restricted)
      assert_empty detail.value.fetch(:available_actions)
    end

    private

    def create_topic_and_post(
      section: @section,
      user: @author,
      status: "published",
      topic_status: "published",
      floor_number: 1
    )
      topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: section,
        user: user,
        title: "Workbench topic #{SecureRandom.hex(3)}",
        status: topic_status,
        last_posted_at: Time.current,
        last_post_user: user,
        replies_count: [ floor_number - 1, 0 ].max
      )
      post = Community::Post.create!(
        topic: topic,
        user: user,
        floor_number: floor_number,
        body: "Workbench evidence body",
        status: status
      )
      [ topic, post ]
    end

    def create_report(reportable)
      Community::Report.create!(
        reporter: create_user,
        reportable: reportable,
        reason_code: "offensive",
        reason: "Reported content evidence."
      )
    end

    def create_quarantined_upload
      Community::Upload.create!(
        user: @author,
        public_id: Community::Upload.generate_public_id,
        kind: "post_attachment",
        status: "stored",
        byte_size: 512,
        scan_status: "infected",
        scan_result_code: "malware_detected",
        quarantined_at: Time.current,
        expires_at: 1.day.from_now
      )
    end

    def create_case(
      source,
      source_kind: "pending_topic",
      section: @section,
      target_user: @author,
      status: "open"
    )
      Community::ModerationCase.create!(
        source: source,
        source_kind: source_kind,
        status: status,
        priority: "normal",
        risk_level: "medium",
        section: section,
        target_user: target_user,
        title: "Case #{source.class.name} #{source.id}",
        summary: "A moderation test case",
        source_updated_at: source.updated_at
      )
    end

    def moderation_case_for(source)
      Community::ModerationCase.find_by!(
        source_type: source.class.base_class.name,
        source_id: source.id
      )
    end

    def assert_case_kind(source, expected)
      assert_equal expected, moderation_case_for(source).source_kind
    end

    def detail_for(actor, moderation_case)
      result = Community::ModerationWorkbench::CaseDetail.call(
        actor: actor,
        moderation_case: moderation_case
      )
      assert_predicate result, :success?, result.error
      result.value
    end

    def manage(
      moderation_case,
      actor:,
      action:,
      lock_version: moderation_case.reload.lock_version,
      **attributes
    )
      Community::ModerationWorkbench::ManageCase.call(
        actor: actor,
        moderation_case: moderation_case,
        action: action,
        lock_version: lock_version,
        **attributes
      )
    end

    def authorize(actor:, action:, cases:, request_id:, reason:, attributes: {})
      Community::ModerationWorkbench::ActionAuthorization.issue(
        actor: actor,
        action: action,
        moderation_cases: cases,
        attributes: attributes,
        request_id: request_id,
        reason: reason
      )
    end

    def action_state(actor, action, cases, attributes = {})
      Community::ModerationWorkbench::ActionPlan.new(
        actor: actor,
        action: action,
        moderation_cases: cases,
        attributes: attributes
      ).state
    end

    def authorize_and_execute(
      actor:,
      action:,
      cases:,
      reason:,
      attributes: {},
      request_id: SecureRandom.uuid
    )
      issued = authorize(
        actor: actor,
        action: action,
        cases: cases,
        attributes: attributes,
        request_id: request_id,
        reason: reason
      )
      assert_predicate issued, :success?, issued.error
      execute(
        actor: actor,
        action: action,
        cases: cases,
        reason: reason,
        attributes: attributes,
        request_id: request_id,
        token: issued.value.fetch(:authorization_token),
        confirmation: issued.value.fetch(:typed_confirmation)
      )
    end

    def execute(
      actor:,
      action:,
      cases:,
      request_id:,
      reason:,
      token:,
      confirmation:,
      attributes: {}
    )
      Community::ModerationWorkbench::ExecuteAction.call(
        actor: actor,
        case_ids: cases.map(&:id),
        action: action,
        request_id: request_id,
        reason: reason,
        attributes: attributes,
        authorization_token: token,
        typed_confirmation: confirmation
      )
    end
  end
end
