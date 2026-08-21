# frozen_string_literal: true

module Commerce
  module Disputes
    class ExecuteAction < ApplicationService
      ACTION_PERMISSIONS = {
        "assign" => "store.disputes.assign",
        "note" => "store.disputes.note",
        "submit_evidence" => "store.disputes.evidence_submit",
        "accept_loss" => "store.disputes.accept_loss",
        "close" => "store.disputes.close",
        "freeze_rights" => "store.disputes.rights_manage",
        "revoke_rights" => "store.disputes.rights_manage",
        "restore_rights" => "store.disputes.rights_manage"
      }.freeze
      DANGEROUS_ACTIONS = %w[
        accept_loss freeze_rights revoke_rights restore_rights
      ].freeze
      ACTIVE_CASE_STATUSES = %w[
        open evidence_required evidence_submitted under_review
      ].freeze
      MAX_NOTE_LENGTH = 5_000

      def initialize(
        actor:,
        dispute:,
        action:,
        request_id:,
        reason:,
        expected_lock_version: nil,
        assignee_id: nil,
        note: nil,
        evidence: {},
        authorization_token: nil,
        confirmation: nil,
        authorize_only: false,
        ip_address: nil,
        user_agent: nil
      )
        @actor = actor
        @dispute = dispute
        @action = action.to_s
        @request_id = Commerce::HighRiskActionAuthorization.normalize_request_id(request_id)
        @reason = reason.to_s.strip
        @expected_lock_version = integer_or_nil(expected_lock_version)
        @assignee_id = integer_or_nil(assignee_id)
        @note = note.to_s.strip
        @evidence = evidence.to_h.symbolize_keys
        @authorization_token = authorization_token
        @confirmation = confirmation
        @authorize_only = authorize_only
        @ip_address = ip_address
        @user_agent = user_agent
      end

      def call
        with_fresh_authorized_actor { call_under_permission_lock }
      end

      def call_under_permission_lock
        existing = existing_event
        return idempotency_result(existing) if existing && !@authorize_only

        @dispute.reload
        validation = validation_failure
        return validation if validation
        return authorize if @authorize_only

        execute
      end

      private :call_under_permission_lock

      private

      def with_fresh_authorized_actor
        Identity::AuthorizedMutation.with(
          actor: @actor,
          all_of: ACTION_PERMISSIONS[@action],
          failure_code: "high_risk_unauthorized"
        ) do |actor|
          @actor = actor
          yield
        end
      end

      def authorize
        return ServiceResult.failure(error: "dispute_action_not_high_risk") unless dangerous?

        Commerce::HighRiskActionAuthorization.issue(
          actor: @actor,
          action: authorization_action,
          targets: targets,
          state: state,
          attributes: attributes,
          request_id: @request_id,
          reason: @reason
        ).then do |result|
          next result unless result.success?

          ServiceResult.success(
            result.value.merge(preview: preview)
          )
        end
      end

      def execute
        result = nil

        Commerce::Dispute.transaction(requires_new: true) do
          _order, _payment, @dispute = Commerce::FinancialLocking.lock_order_payment_dispute!(
            order_id: @dispute.store_order_id,
            payment_record_id: @dispute.payment_record_id,
            dispute_id: @dispute.id
          )

          existing = existing_event
          if existing
            result = idempotency_result(existing)
            next
          end

          if @expected_lock_version.present? &&
              @expected_lock_version != @dispute.lock_version
            result = ServiceResult.failure(error: "dispute_state_changed")
            next
          end
          if dangerous? && !authorization_valid?
            result = ServiceResult.failure(error: "high_risk_authorization_invalid")
            next
          end
          if dangerous? && !confirmation_valid?
            result = ServiceResult.failure(error: "high_risk_confirmation_invalid")
            next
          end

          state_failure = action_state_failure
          if state_failure
            result = state_failure
            next
          end

          before = audit_state
          action_result = apply_action!
          event = Commerce::DisputeEvent.create!(
            dispute: @dispute,
            actor: @actor,
            idempotency_key: event_idempotency_key,
            request_id: @request_id,
            source: "manual",
            event_type: @action,
            from_status: before.fetch(:status),
            to_status: @dispute.status,
            note: event_note,
            metadata: {
              "request_fingerprint" => request_fingerprint,
              "action" => @action,
              "evidence_id" => action_result[:evidence]&.id,
              "assignee_id" => @dispute.assigned_to_id,
              "rights_status" => @dispute.rights_status,
              "confirmation_method" => ("signed_typed_challenge" if dangerous?)
            }.compact
          )
          Administration::AuditLogger.call(
            actor: @actor,
            action: "commerce.dispute_#{@action}",
            resource: @dispute,
            request_id: @request_id,
            reason: @reason,
            before_state: before,
            after_state: audit_state,
            metadata: {
              dispute_event_id: event.id,
              evidence_id: action_result[:evidence]&.id,
              confirmation_method: ("signed_typed_challenge" if dangerous?)
            }.compact,
            ip_address: @ip_address,
            user_agent: @user_agent
          )

          result = ServiceResult.success(
            dispute: @dispute,
            event: event,
            evidence: action_result[:evidence],
            idempotent: false,
            action: @action
          )
        end

        result
      rescue Commerce::FinancialLocking::BindingMismatch
        ServiceResult.failure(error: "dispute_payment_binding_mismatch")
      rescue ActiveRecord::RecordNotUnique
        idempotency_result(existing_event)
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(errors: error.record.errors.to_hash)
      end

      def apply_action!
        evidence = nil

        case @action
        when "assign"
          @dispute.update!(assigned_to_id: @assignee_id)
        when "note"
          bump_manual_revision!
        when "submit_evidence"
          evidence = create_evidence!
          @dispute.update!(
            status: evidence_status,
            metadata: @dispute.metadata.merge(
              "latest_evidence_id" => evidence.id,
              "latest_evidence_submitted_at" => evidence.submitted_at.iso8601(6)
            )
          )
        when "accept_loss"
          @dispute.update!(
            status: "lost",
            resolution: "accepted_loss",
            accepted_loss_at: Time.current,
            accepted_loss_by: @actor
          )
          apply_rights!("revoke")
        when "close"
          close_at = Time.current
          retention_until = close_at + Commerce::Dispute::RETENTION_PERIOD
          @dispute.update!(
            status: "closed",
            closed_at: close_at,
            closed_by: @actor,
            retention_until: retention_until
          )
          @dispute.evidence.find_each do |item|
            item.update!(retention_until: retention_until)
          end
        when "freeze_rights"
          apply_rights!("freeze")
        when "revoke_rights"
          apply_rights!("revoke")
        when "restore_rights"
          apply_rights!("restore")
        end

        { evidence: evidence }
      end

      def bump_manual_revision!
        @dispute.update!(
          metadata: @dispute.metadata.merge(
            "latest_manual_note_at" => Time.current.iso8601(6)
          )
        )
      end

      def create_evidence!
        body = @evidence[:content].to_s
        filename = safe_filename(@evidence[:filename])
        Commerce::DisputeEvidence.create!(
          dispute: @dispute,
          submitted_by: @actor,
          idempotency_key: "#{event_idempotency_key}:evidence",
          title: @evidence[:title].to_s.strip,
          filename: filename,
          content_type: normalized_content_type,
          content: body,
          byte_size: body.bytesize,
          sha256: Digest::SHA256.hexdigest(body),
          submission_status: "submitted",
          submitted_at: Time.current,
          retention_until: @dispute.retention_until
        )
      end

      def apply_rights!(action)
        result = Commerce::Disputes::RightsPolicy.call(
          dispute: @dispute,
          action: action,
          idempotency_prefix: event_idempotency_key,
          actor: @actor,
          reason: @reason
        )
        return if result.success?

        @dispute.errors.add(:base, result.error.presence || "rights action failed")
        raise ActiveRecord::RecordInvalid.new(@dispute)
      end

      def validation_failure
        return ServiceResult.failure(error: "dispute_action_invalid") unless ACTION_PERMISSIONS.key?(@action)
        return ServiceResult.failure(error: "high_risk_unauthorized") unless @actor&.permission?(permission)
        return ServiceResult.failure(error: "high_risk_request_id_invalid") unless @request_id
        return ServiceResult.failure(error: "high_risk_reason_required") if @reason.blank?
        if @reason.length > Commerce::HighRiskActionAuthorization::MAX_REASON_LENGTH
          return ServiceResult.failure(error: "high_risk_reason_too_long")
        end

        action_state_failure
      end

      def action_state_failure
        case @action
        when "assign"
          return ServiceResult.failure(error: "dispute_closed") if @dispute.closed?
          return ServiceResult.failure(error: "dispute_assignee_invalid") unless User.exists?(id: @assignee_id)
        when "note"
          return ServiceResult.failure(error: "dispute_note_required") if @note.blank?
          return ServiceResult.failure(error: "dispute_note_too_long") if @note.length > MAX_NOTE_LENGTH
        when "submit_evidence"
          return ServiceResult.failure(error: "dispute_evidence_state_invalid") unless ACTIVE_CASE_STATUSES.include?(@dispute.status)
          return evidence_validation_failure if evidence_validation_failure
        when "accept_loss"
          return ServiceResult.failure(error: "dispute_accept_loss_state_invalid") unless ACTIVE_CASE_STATUSES.include?(@dispute.status)
          return ServiceResult.failure(error: "dispute_no_financial_exposure") unless @dispute.liability_cents.positive?
        when "close"
          return ServiceResult.failure(error: "dispute_close_state_invalid") unless %w[won lost withdrawn].include?(@dispute.status)
        when "freeze_rights", "revoke_rights"
          return ServiceResult.failure(error: "dispute_rights_state_invalid") unless ACTIVE_CASE_STATUSES.include?(@dispute.status) || @dispute.lost?
        when "restore_rights"
          unless @dispute.rights_frozen? || @dispute.rights_revoked?
            return ServiceResult.failure(error: "dispute_rights_state_invalid")
          end
        end

        nil
      end

      def evidence_validation_failure
        title = @evidence[:title].to_s.strip
        content = @evidence[:content].to_s
        return ServiceResult.failure(error: "dispute_evidence_title_required") if title.blank?
        return ServiceResult.failure(error: "dispute_evidence_content_required") if content.blank?
        if content.bytesize > Commerce::DisputeEvidence::MAX_BYTES
          return ServiceResult.failure(error: "dispute_evidence_too_large")
        end
        return ServiceResult.failure(error: "dispute_evidence_type_invalid") unless Commerce::DisputeEvidence::CONTENT_TYPES.include?(normalized_content_type)

        nil
      end

      def evidence_status
        return @dispute.status if %w[evidence_submitted under_review].include?(@dispute.status)

        "evidence_submitted"
      end

      def existing_event
        Commerce::DisputeEvent.find_by(idempotency_key: event_idempotency_key)
      end

      def idempotency_result(event)
        return ServiceResult.failure(error: "dispute_idempotency_conflict") unless event
        return ServiceResult.failure(error: "dispute_idempotency_conflict") unless secure_match?(
          event.metadata["request_fingerprint"],
          request_fingerprint
        )

        ServiceResult.success(
          dispute: event.dispute,
          event: event,
          evidence: event.metadata["evidence_id"].present? ?
            Commerce::DisputeEvidence.find_by(id: event.metadata["evidence_id"]) :
            nil,
          idempotent: true,
          action: event.metadata["action"]
        )
      end

      def permission
        ACTION_PERMISSIONS.fetch(@action)
      end

      def dangerous?
        DANGEROUS_ACTIONS.include?(@action)
      end

      def authorization_action
        case @action
        when "accept_loss" then "dispute.accept_loss"
        when "freeze_rights" then "dispute.rights.freeze"
        when "revoke_rights" then "dispute.rights.revoke"
        when "restore_rights" then "dispute.rights.restore"
        end
      end

      def authorization_valid?
        Commerce::HighRiskActionAuthorization.valid?(
          @authorization_token,
          actor: @actor,
          action: authorization_action,
          targets: targets,
          state: state,
          attributes: attributes,
          request_id: @request_id,
          reason: @reason
        )
      end

      def confirmation_valid?
        Commerce::HighRiskActionAuthorization.confirmation_valid?(
          @confirmation,
          action: authorization_action,
          targets: targets,
          request_id: @request_id
        )
      end

      def targets
        [ { "type" => "dispute", "public_id" => @dispute.public_id } ]
      end

      def state
        {
          "lock_version" => @dispute.lock_version,
          "status" => @dispute.status,
          "resolution" => @dispute.resolution,
          "liability_cents" => @dispute.liability_cents,
          "rights_status" => @dispute.rights_status
        }
      end

      def attributes
        {
          "action" => @action,
          "assignee_id" => @assignee_id,
          "note_digest" => digest(@note),
          "evidence_digest" => digest(@evidence.to_h.deep_stringify_keys)
        }
      end

      def request_fingerprint
        Commerce::HighRiskActionAuthorization.request_fingerprint(
          actor: @actor,
          action: dangerous? ? authorization_action : "dispute.#{@action}",
          targets: targets,
          attributes: attributes,
          request_id: @request_id,
          reason: @reason
        ) || Digest::SHA256.hexdigest(
          JSON.generate(
            {
              actor_id: @actor&.id,
              action: @action,
              targets: targets,
              attributes: attributes,
              request_id: @request_id,
              reason: @reason
            }
          )
        )
      end

      def preview
        {
          dispute_public_id: @dispute.public_id,
          order_number: @dispute.order.order_number,
          action: @action,
          current_status: @dispute.status,
          next_status: @action == "accept_loss" ? "lost" : @dispute.status,
          amount_cents: @dispute.amount_cents,
          liability_cents: @dispute.liability_cents,
          currency: @dispute.currency,
          rights_status: @dispute.rights_status
        }
      end

      def audit_state
        {
          status: @dispute.status,
          resolution: @dispute.resolution,
          assigned_to_id: @dispute.assigned_to_id,
          amount_cents: @dispute.amount_cents,
          liability_cents: @dispute.liability_cents,
          offset_cents: @dispute.offset_cents,
          rights_status: @dispute.rights_status,
          lock_version: @dispute.lock_version
        }
      end

      def event_note
        @action == "note" ? @note : @reason
      end

      def event_idempotency_key
        "dispute-manual:#{@request_id}"
      end

      def normalized_content_type
        @evidence[:content_type].to_s.presence || "text/plain"
      end

      def safe_filename(value)
        basename = File.basename(value.to_s.presence || "evidence.txt")
        basename.gsub(/[^a-zA-Z0-9_.-]+/, "_").first(120).presence || "evidence.txt"
      end

      def digest(value)
        Digest::SHA256.hexdigest(JSON.generate(value))
      end

      def integer_or_nil(value)
        Integer(value) if value.present?
      rescue ArgumentError, TypeError
        nil
      end

      def secure_match?(left, right)
        left = left.to_s
        right = right.to_s
        left.bytesize == right.bytesize &&
          ActiveSupport::SecurityUtils.secure_compare(left, right)
      end
    end
  end
end
