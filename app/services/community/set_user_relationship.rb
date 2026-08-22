# frozen_string_literal: true

module Community
  class SetUserRelationship < ApplicationService
    MAX_WRITE_ATTEMPTS = 3

    def initialize(relation:, desired_state:)
      @relation = relation
      @desired_state = desired_state
    end

    def call
      return ServiceResult.failure(error: :relationship_state_required) unless [ true, false ].include?(@desired_state)

      changed = @desired_state ? ensure_present! : @relation.delete_all.positive?
      ServiceResult.success(active: @relation.exists?, changed: changed)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique
      ServiceResult.failure(error: :relationship_update_conflict, code: "conflict")
    end

    private

    def ensure_present!
      attempts = 0

      begin
        record = @relation.create_or_find_by!
        record.previously_new_record?
      rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < MAX_WRITE_ATTEMPTS

        raise
      end
    end
  end
end
