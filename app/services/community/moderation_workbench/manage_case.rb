# frozen_string_literal: true

module Community
  module ModerationWorkbench
    class ManageCase < ApplicationService
      ACTIONS = %w[claim assign note].freeze

      def initialize(actor:, moderation_case:, action:, lock_version:, assignee_id: nil,
                     body: nil, ip_address: nil, user_agent: nil)
        @actor = actor
        @moderation_case = moderation_case
        @action = action.to_s
        @expected_lock_version = Integer(lock_version, exception: false)
        @assignee_id = assignee_id
        @body = body.to_s.strip
        @ip_address = ip_address
        @user_agent = user_agent
        @policy = Policy.new(actor)
      end

      def call
        return failure("moderation_case_action_invalid") unless ACTIONS.include?(@action)
        return failure("moderation_case_forbidden") unless @policy.can_manage_case?(@moderation_case)
        return failure("moderation_case_version_required") if @expected_lock_version.nil?

        note = nil
        Community::ModerationCase.transaction do
          locked = Community::ModerationCase.lock.find(@moderation_case.id)
          return failure("moderation_case_conflict") unless locked.lock_version == @expected_lock_version
          return failure("moderation_case_closed") unless locked.status.in?(Community::ModerationCase::ACTIVE_STATUSES)
          lock_live_scope!(locked)
          unless Policy.new(@actor).can_manage_case?(locked)
            return failure("moderation_case_forbidden")
          end

          before_state = assignment_state(locked)
          case @action
          when "claim"
            return failure("moderation_case_already_claimed") if locked.assignee_id.present? &&
              locked.assignee_id != @actor.id

            locked.update!(
              assignee: @actor,
              status: "claimed",
              claimed_at: locked.claimed_at || Time.current
            )
          when "assign"
            assignee = find_assignee
            return failure("moderation_case_assignee_invalid") if @assignee_id.present? && !assignee
            return failure("moderation_case_assignee_forbidden") unless @policy.can_assign?(locked, assignee)

            locked.update!(
              assignee: assignee,
              status: assignee ? "claimed" : "open",
              claimed_at: assignee ? (locked.claimed_at || Time.current) : nil
            )
          when "note"
            return failure("moderation_case_note_required") if @body.blank?
            return failure("moderation_case_note_too_long") if @body.length > 2_000

            note = locked.notes.create!(author: @actor, body: @body)
            locked.touch
          end

          Administration::AuditLogger.call(
            actor: @actor,
            action: "admin.forum_moderation_case_#{@action}",
            resource: locked,
            metadata: {
              moderation_case_id: locked.id,
              source_kind: locked.source_kind,
              note_id: note&.id,
              note_length: note&.body&.length
            }.compact,
            before_state: before_state,
            after_state: assignment_state(locked),
            ip_address: @ip_address,
            user_agent: @user_agent
          )
          @moderation_case = locked
        end

        ServiceResult.success(
          moderation_case: @moderation_case.reload,
          note: note
        )
      rescue ActiveRecord::RecordNotFound
        failure("moderation_case_stale")
      rescue ActiveRecord::StaleObjectError
        failure("moderation_case_conflict")
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(
          error: "moderation_case_update_failed",
          errors: error.record.errors.to_hash
        )
      end

      private

      def find_assignee
        id = Integer(@assignee_id, exception: false)
        id&.positive? ? User.find_by(id: id) : nil
      end

      def lock_live_scope!(moderation_case)
        source = moderation_case.source
        reportable = source.reportable if source.is_a?(Community::Report)
        posts = [ source, reportable ].grep(Community::Post)
        topics = [ source, reportable ].grep(Community::Topic) +
          posts.filter_map(&:topic)

        Community::Topic.with_discarded
          .where(id: topics.map(&:id).uniq.sort)
          .order(:id)
          .lock
          .load
        Community::Post.with_discarded
          .where(id: posts.map(&:id).uniq.sort)
          .order(:id)
          .lock
          .load
        if source.is_a?(Community::Report)
          Community::Report.where(id: source.id).lock.load
        end
        moderation_case.association(:source).reset
      rescue ActiveRecord::RecordNotFound
        moderation_case.association(:source).reset
      end

      def assignment_state(moderation_case)
        {
          status: moderation_case.status,
          assignee_id: moderation_case.assignee_id,
          claimed_at: moderation_case.claimed_at&.iso8601,
          lock_version: moderation_case.lock_version
        }
      end

      def failure(error)
        ServiceResult.failure(error: error)
      end
    end
  end
end
