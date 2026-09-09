# frozen_string_literal: true

module Community
  class SetUserRelationship < ApplicationService
    MAX_WRITE_ATTEMPTS = 3
    PARTICIPANT_ID_READERS = {
      "Community::UserBlock" => %i[blocker_id blocked_id],
      "Community::UserFollow" => %i[follower_id followed_id],
      "Community::UserIgnore" => %i[ignorer_id ignored_id]
    }.freeze

    def initialize(relation:, desired_state:, expected_revision: nil, participants: nil)
      @relation = relation
      @desired_state = desired_state
      @expected_revision = expected_revision
      @participants = participants
    end

    def call
      return ServiceResult.failure(error: :relationship_state_required) unless [ true, false ].include?(@desired_state)

      # Keep relationship + revision atomic even when an outer service opens a
      # transaction and then handles this service's failure result.
      ApplicationRecord.transaction(requires_new: true) do
        ::Identity::UserMutationLock.with_users(users: lock_participant_ids) do
          ApplicationRecord.uncached { mutate_locked }
        end
      end
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique
      ServiceResult.failure(error: :relationship_update_conflict, code: "conflict")
    end

    private

    def mutate_locked
      key = UserRelationshipState.key_for(@relation)
      ledger = UserRelationshipState.find_or_initialize_by(key)
      snapshot = { active: @relation.exists?, revision: ledger.revision.to_s }
      expected = normalized_expected_revision
      unless expected
        return ServiceResult.failure(
          error: :relationship_revision_required, code: "precondition_required", value: snapshot
        )
      end

      # The pair (expected revision, desired state) identifies one intent. A
      # replay of the immediately preceding intent is a no-op, even if the
      # response to its first attempt was lost. Older intents must not run again.
      if expected == ledger.revision - 1 && ledger.last_desired_state == @desired_state && snapshot[:active] == @desired_state
        return ServiceResult.success(snapshot.merge(changed: false, replayed: true))
      end

      unless expected == ledger.revision
        return ServiceResult.failure(error: :relationship_update_conflict, code: "conflict", value: snapshot)
      end

      changed = @desired_state ? ensure_present! : @relation.delete_all.positive?
      # Advance even for a no-op: a newly confirmed intent supersedes every
      # older one. Keep the ledger after DELETE to prevent absent-state ABA.
      ledger.update!(revision: ledger.revision + 1, last_desired_state: @desired_state)
      ServiceResult.success(active: @relation.exists?, revision: ledger.revision.to_s, changed: changed, replayed: false)
    end

    def normalized_expected_revision
      value = @expected_revision
      return unless value.is_a?(String) || value.is_a?(Integer)
      return unless value.to_s.match?(/\A(?:0|[1-9][0-9]{0,18})\z/)

      revision = value.to_i
      revision if revision < 9_223_372_036_854_775_807
    end

    def lock_participant_ids
      # The scoped relationship is the source of truth so legacy callers cannot bypass participant locking.
      readers = PARTICIPANT_ID_READERS.fetch(@relation.klass.name) do
        raise ArgumentError, "community_user_relationship_participants_required"
      end
      scoped_record = @relation.new
      derived_ids = normalize_participant_ids(readers.map { |reader| scoped_record.public_send(reader) })
      raise ArgumentError, "community_user_relationship_participants_required" unless derived_ids

      provided_ids = @participants.nil? ? derived_ids : normalize_participant_ids(@participants)
      unless provided_ids == derived_ids
        raise ArgumentError, "community_user_relationship_participants_mismatch"
      end

      derived_ids
    end

    def normalize_participant_ids(participants)
      values = Array(participants).flatten
      return if values.empty?

      values.map do |participant|
        raw_id = participant.respond_to?(:id) ? participant.id : participant
        user_id = Integer(raw_id, exception: false)
        return unless user_id&.positive?

        user_id
      end.uniq.sort
    end

    def ensure_present!
      attempts = 0

      begin
        record = @relation.create_or_find_by!({})
        record.previously_new_record?
      rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < MAX_WRITE_ATTEMPTS

        raise
      end
    end
  end
end
