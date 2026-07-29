# frozen_string_literal: true

module Community
  module ModerationWorkbench
    class ExecuteAction < ApplicationService
      class DispositionFailure < StandardError
        attr_reader :case_id, :code

        def initialize(case_id, code)
          @case_id = case_id
          @code = code
          super(code)
        end
      end

      def initialize(actor:, case_ids:, action:, request_id:, reason:, attributes: {},
                     authorization_token:, typed_confirmation:, ip_address: nil,
                     user_agent: nil)
        @actor = actor
        @case_ids = ActionAuthorization.normalize_case_ids(case_ids)
        @action = action.to_s.strip.downcase
        @request_id = ActionAuthorization.normalize_request_id(request_id)
        @reason = ActionAuthorization.normalize_reason(reason)
        @attributes = ActionAuthorization.canonicalize(attributes)
        @authorization_token = authorization_token.to_s
        @typed_confirmation = typed_confirmation.to_s.strip
        @ip_address = ip_address
        @user_agent = user_agent
        @results = []
        @performed_targets = {}
      end

      def call
        validation = validation_failure
        return validation if validation

        @request_fingerprint = request_fingerprint
        existing = Community::ModerationOperation.find_by(request_id: @request_id)
        return idempotency_result(existing) if existing
        return failure("moderation_authorization_required") if @authorization_token.blank?
        unless ActionAuthorization.confirmation_valid?(
          @typed_confirmation,
          action: @action,
          case_ids: @case_ids,
          request_id: @request_id
        )
          return failure("moderation_confirmation_invalid")
        end

        operation = nil
        Mcweb::Events.defer_until_success do
          Community::ModerationOperation.transaction do
            cases = lock_cases
            unless cases.size == @case_ids.size
              raise DispositionFailure.new(nil, "moderation_cases_not_found")
            end

            existing = Community::ModerationOperation.find_by(request_id: @request_id)
            return idempotency_result(existing) if existing

            lock_action_records!(cases)
            cases.each do |moderation_case|
              moderation_case.association(:source).reset
              moderation_case.association(:target_user).reset
            end
            plan = ActionPlan.new(
              actor: @actor,
              action: @action,
              moderation_cases: cases,
              attributes: @attributes
            )
            authorized_state = plan.state
            unless ActionAuthorization.valid?(
              @authorization_token,
              actor: @actor,
              action: @action,
              moderation_cases: cases,
              state: authorized_state,
              attributes: @attributes,
              request_id: @request_id,
              reason: @reason
            )
              raise DispositionFailure.new(nil, "moderation_authorization_invalid")
            end

            preview = plan.preview
            prepare_target_counts(cases, plan, preview)
            preview.each do |item|
              moderation_case = cases.find { |candidate| candidate.id == item.fetch(:case_id) }
              unless item.fetch(:eligible)
                @results << result_item(
                  moderation_case,
                  status: "skipped",
                  message: item.fetch(:message)
                )
                next
              end

              @current_case_id = moderation_case.id
              before_state = audit_state(moderation_case)
              action_result, shared_target, shared_message =
                perform_action_once(moderation_case, plan)
              if action_result.failure?
                raise DispositionFailure.new(
                  moderation_case.id,
                  action_result.error.presence || "moderation_action_failed"
                )
              end

              update_case_after_action!(moderation_case)
              Administration::AuditLogger.call(
                actor: @actor,
                action: "admin.forum_moderation_workbench_#{@action}",
                resource: moderation_case,
                reason: @reason,
                metadata: {
                  moderation_case_id: moderation_case.id,
                  source_kind: moderation_case.source_kind,
                  source_type: moderation_case.source_type,
                  source_id: moderation_case.source_id,
                  request_id: @request_id,
                  confirmation_method: "signed_typed_challenge",
                  shared_target: shared_target,
                  attributes: audit_attributes
                }.compact,
                before_state: before_state,
                after_state: audit_state(moderation_case),
                ip_address: @ip_address,
                user_agent: @user_agent
              )
              @results << result_item(
                moderation_case,
                status: "success",
                message: shared_message || item.fetch(:message),
                shared_target: shared_target
              )
            end

            operation = Community::ModerationOperation.create!(
              actor: @actor,
              action: @action,
              request_id: @request_id,
              request_fingerprint: @request_fingerprint,
              authorization_digest: ActionAuthorization.authorization_digest(
                @authorization_token
              ),
              reason: @reason,
              target_snapshot: plan.targets.map do |target|
                target.merge(
                  state: authorized_state.find do |state|
                    state.fetch(:case_id) == target.fetch(:case_id)
                  end
                )
              end,
              result_snapshot: @results,
              metadata: {
                confirmation_method: "signed_typed_challenge",
                case_count: cases.size,
                successful_count: @results.count { |item| item[:status] == "success" },
                skipped_count: @results.count { |item| item[:status] == "skipped" },
                attributes: audit_attributes
              }
            )
          end
        end

        ServiceResult.success(
          request_id: @request_id,
          replayed: false,
          results: @results,
          operation_id: operation.id
        )
      rescue DispositionFailure => error
        rolled_back_results(error)
      rescue ActiveRecord::RecordNotUnique
        existing = Community::ModerationOperation.find_by(request_id: @request_id)
        return idempotency_result(existing) if existing

        failure("moderation_authorization_replayed")
      rescue StandardError => error
        Rails.logger.error(
          "[Community::ModerationWorkbench::ExecuteAction] transaction rolled back " \
          "request_id=#{@request_id} case_id=#{@current_case_id} error=#{error.class}"
        )
        rolled_back_results(
          DispositionFailure.new(@current_case_id, "moderation_action_transaction_failed")
        )
      end

      private

      def validation_failure
        return failure("moderation_action_invalid") unless ActionPlan::ACTIONS.include?(@action)
        return failure("moderation_cases_required") if @case_ids.empty?
        return failure("moderation_too_many_cases") if @case_ids.size > ActionAuthorization::MAX_CASES
        return failure("moderation_request_id_invalid") unless @request_id
        return failure("moderation_reason_required") if @reason.blank?
        return failure("moderation_reason_too_long") if @reason.length > ActionAuthorization::MAX_REASON_LENGTH
        return failure("moderation_actor_required") unless @actor

        nil
      end

      def lock_cases
        Community::ModerationCase
          .where(id: @case_ids)
          .order(:id)
          .lock
          .to_a
      end

      # Lock mutable moderation targets in a stable order before validating the
      # signed state snapshot. Existing services can safely re-enter these locks.
      def lock_action_records!(cases)
        sources = cases.filter_map do |moderation_case|
          moderation_case.source
        rescue ActiveRecord::RecordNotFound
          nil
        end
        reports = sources.grep(Community::Report)
        reportables = reports.filter_map(&:reportable)
        posts = (sources + reportables).grep(Community::Post)
        topics = (sources + reportables).grep(Community::Topic) + posts.filter_map(&:topic)
        users = sources.grep(User) +
          sources.filter_map { |source| target_user_for_lock(source) }

        Community::Topic.with_discarded.where(id: topics.map(&:id).uniq.sort).order(:id).lock.load
        Community::Post.with_discarded.where(id: posts.map(&:id).uniq.sort).order(:id).lock.load
        Community::Report.where(id: reports.map(&:id).uniq.sort).order(:id).lock.load
        Community::Upload.where(id: sources.grep(Community::Upload).map(&:id).uniq.sort).order(:id).lock.load
        Community::UserWarning.where(
          id: sources.grep(Community::UserWarning).map(&:id).uniq.sort
        ).order(:id).lock.load
        Community::Mute.where(id: sources.grep(Community::Mute).map(&:id).uniq.sort).order(:id).lock.load
        User.where(id: users.compact.map(&:id).uniq.sort).order(:id).lock.load

        sources.each(&:reload)
        reports.each { |report| report.association(:reportable).reset }
      end

      def perform_action(moderation_case, plan)
        return ServiceResult.success(moderation_case) if @action.in?(%w[resolve_case dismiss_case])

        source = moderation_case.source
        case @action
        when "approve"
          Community::ApprovePost.call(actor: @actor, post: source)
        when "reject"
          Community::RejectPost.call(actor: @actor, post: source, reason: @reason)
        when "resolve_report"
          decide_report(source, status: :actioned)
        when "dismiss_report"
          decide_report(source, status: :dismissed)
        when "delete_content"
          delete_content(source, plan.content_target(source))
        when "move_topic"
          Community::MoveTopic.call(
            user: @actor,
            topic: plan.topic_target(source),
            section: plan.destination_section,
            leave_redirect: truthy?(@attributes["leave_redirect"])
          )
        when "release_attachment"
          Community::ReleaseQuarantinedUpload.call(
            upload: source,
            actor: @actor,
            confirmation: Community::ReleaseQuarantinedUpload.confirmation_for(source),
            reason: @reason,
            ip_address: @ip_address,
            user_agent: @user_agent
          )
        when "delete_attachment"
          schedule_attachment_cleanup(source)
        when "warn_user"
          Community::CreateUserWarning.call(
            actor: @actor,
            user: plan.target_user(source),
            reason: @reason,
            points: plan.warning_points,
            expire_days: plan.warning_expire_days
          )
        when "mute_user"
          Community::CreateMute.call(
            actor: @actor,
            user: plan.target_user(source),
            section: nil,
            reason: @reason,
            expires_at: plan.duration_days.days.from_now
          )
        when "ban_user"
          return failure("moderation_ban_forbidden") unless @actor.account_owner?

          Administration::BanUser.call(
            user: plan.target_user(source),
            actor: @actor,
            reason: @reason,
            expires_at: plan.duration_days.zero? ? nil : plan.duration_days.days.from_now
          )
        else
          failure("moderation_action_invalid")
        end
      end

      def perform_action_once(moderation_case, plan)
        target_key = plan.mutation_target_key(moderation_case)
        if target_key && @action == "dismiss_report" &&
            @remaining_target_counts.fetch(target_key, 0) > 1
          @remaining_target_counts[target_key] -= 1
          return [
            decide_report(
              moderation_case.source,
              status: :dismissed,
              mutate_reportable: false
            ),
            true,
            "shared_target_action_deferred"
          ]
        end
        @remaining_target_counts[target_key] -= 1 if target_key

        if target_key && @performed_targets.key?(target_key)
          return [
            perform_shared_target_followup(moderation_case),
            true,
            "shared_target_already_actioned"
          ]
        end

        result = perform_action(moderation_case, plan)
        @performed_targets[target_key] = true if target_key && result.success?
        [ result, false, nil ]
      end

      def prepare_target_counts(cases, plan, preview)
        @remaining_target_counts = Hash.new(0)
        preview.each do |item|
          next unless item.fetch(:eligible)

          moderation_case = cases.find { |candidate| candidate.id == item.fetch(:case_id) }
          target_key = plan.mutation_target_key(moderation_case)
          @remaining_target_counts[target_key] += 1 if target_key
        end
      end

      def perform_shared_target_followup(moderation_case)
        source = moderation_case.source
        case @action
        when "resolve_report"
          decide_report(source, status: :actioned, mutate_reportable: false)
        when "dismiss_report"
          decide_report(source, status: :dismissed, mutate_reportable: false)
        when "delete_content"
          if source.is_a?(Community::Report) && source.status == "pending"
            source.review!(reviewer: @actor, note: @reason, status: :actioned)
          end
          ServiceResult.success(source)
        else
          ServiceResult.success(source)
        end
      end

      def decide_report(report, status:, mutate_reportable: true)
        return failure("report_not_pending") unless report.status == "pending"

        report.review!(reviewer: @actor, note: @reason, status: status)
        return ServiceResult.success(report) unless mutate_reportable

        result =
          if status == :actioned
            Community::HideReportable.call(reportable: report.reportable)
          else
            Community::ClearReportableHide.call(reportable: report.reportable)
          end
        return result if result.failure?

        ServiceResult.success(report)
      end

      def delete_content(source, target)
        return failure("moderation_content_not_supported") unless target

        result =
          case target
          when Community::Post
            target.floor_number == 1 ? soft_delete_topic(target.topic) :
              Community::DeletePost.call(actor: @actor, post: target)
          when Community::Topic
            soft_delete_topic(target)
          else
            failure("moderation_content_not_supported")
          end
        return result if result.failure?

        if source.is_a?(Community::Report) && source.status == "pending"
          source.review!(reviewer: @actor, note: @reason, status: :actioned)
        end
        ServiceResult.success(target)
      end

      def soft_delete_topic(topic)
        unless Community::SectionModeration.can_moderate_topic?(user: @actor, topic: topic)
          return failure("moderation_delete_forbidden")
        end

        now = Time.current
        topic.update!(status: "deleted", deleted_at: now)
        Community::Post.with_discarded.where(forum_topic_id: topic.id).update_all(
          status: "deleted",
          deleted_at: now,
          updated_at: now
        )
        Community::DispatchForumEventWebhook.call(
          event_type: "topic.deleted",
          topic: topic
        )
        ServiceResult.success(topic)
      end

      def schedule_attachment_cleanup(upload)
        return failure("moderation_attachment_delete_forbidden") unless
          @actor.permission?(Policy::ATTACHMENT_MANAGE_PERMISSION)
        return failure("attachment_already_cleaned") if upload.status_cleaned?

        upload.update!(
          status: "cleanup_pending",
          expires_at: Time.current,
          cleanup_started_at: nil,
          cleanup_error_code: nil,
          cleanup_error_message: nil
        )
        Maintenance::CleanupForumUploadsJob.perform_later(upload_id: upload.id)
        ServiceResult.success(upload)
      end

      def update_case_after_action!(moderation_case)
        status =
          case @action
          when "dismiss_case", "dismiss_report" then "dismissed"
          when "resolve_case" then "resolved"
          when *ActionPlan::CLOSING_ACTIONS then "actioned"
          else moderation_case.status
          end
        source_updated_at = moderation_case.source&.updated_at || moderation_case.source_updated_at
        moderation_case.update!(
          status: status,
          resolved_at: status.in?(Community::ModerationCase::ACTIVE_STATUSES) ? nil : Time.current,
          last_action: @action,
          last_reason: @reason,
          source_updated_at: source_updated_at
        )
      end

      def audit_state(moderation_case)
        {
          status: moderation_case.status,
          assignee_id: moderation_case.assignee_id,
          last_action: moderation_case.last_action,
          source_type: moderation_case.source_type,
          source_id: moderation_case.source_id,
          source_updated_at: moderation_case.source_updated_at&.iso8601(6),
          lock_version: moderation_case.lock_version
        }
      end

      def audit_attributes
        @attributes.slice(
          "section_id", "leave_redirect", "points", "expire_days", "duration_days"
        )
      end

      def request_fingerprint
        ActionAuthorization.request_fingerprint(
          actor: @actor,
          action: @action,
          case_ids: @case_ids,
          attributes: @attributes,
          request_id: @request_id,
          reason: @reason
        )
      end

      def idempotency_result(existing)
        return failure("moderation_request_id_reused") unless existing
        unless secure_match?(existing.request_fingerprint, @request_fingerprint || request_fingerprint)
          return failure("moderation_request_id_reused")
        end

        ServiceResult.success(
          request_id: existing.request_id,
          replayed: true,
          results: existing.result_snapshot,
          operation_id: existing.id
        )
      end

      def rolled_back_results(error)
        affected_ids = @case_ids
        current = @results.index_by { |item| item[:case_id] || item["case_id"] }
        results = affected_ids.map do |case_id|
          existing = current[case_id]
          if case_id == error.case_id
            { case_id: case_id, status: "failed", message: error.code }
          elsif existing && (existing[:status] || existing["status"]) == "skipped"
            existing
          else
            { case_id: case_id, status: "rolled_back", message: error.code }
          end
        end
        ServiceResult.failure(
          error: error.code,
          value: { request_id: @request_id, replayed: false, results: results }
        )
      end

      def result_item(moderation_case, status:, message:, shared_target: false)
        result = {
          case_id: moderation_case.id,
          status: status,
          message: message,
          lock_version: moderation_case.lock_version
        }
        result[:shared_target] = true if shared_target
        result
      end

      def target_user_for_lock(source)
        ActionPlan.new(
          actor: @actor,
          action: @action,
          moderation_cases: [],
          attributes: @attributes
        ).target_user(source)
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end

      def secure_match?(left, right)
        left = left.to_s
        right = right.to_s
        left.bytesize == right.bytesize &&
          ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def failure(error)
        ServiceResult.failure(error: error)
      end
    end
  end
end
