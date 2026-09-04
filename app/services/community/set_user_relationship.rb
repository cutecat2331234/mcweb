# frozen_string_literal: true

module Community
  class SetUserRelationship < ApplicationService
    MAX_WRITE_ATTEMPTS = 3
    PARTICIPANT_ID_READERS = {
      "Community::UserBlock" => %i[blocker_id blocked_id],
      "Community::UserFollow" => %i[follower_id followed_id],
      "Community::UserIgnore" => %i[ignorer_id ignored_id]
    }.freeze

    def initialize(relation:, desired_state:, participants: nil)
      @relation = relation
      @desired_state = desired_state
      @participants = participants
    end

    def call
      return ServiceResult.failure(error: :relationship_state_required) unless [ true, false ].include?(@desired_state)

      ::Identity::UserMutationLock.with_users(users: lock_participant_ids) do
        changed = @desired_state ? ensure_present! : @relation.delete_all.positive?
        ServiceResult.success(active: @relation.exists?, changed: changed)
      end
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique
      ServiceResult.failure(error: :relationship_update_conflict, code: "conflict")
    end

    private

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
