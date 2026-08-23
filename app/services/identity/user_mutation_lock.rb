# frozen_string_literal: true

module Identity
  class UserMutationLock
    class << self
      def with_users(users:)
        user_ids = normalized_user_ids(users)

        ApplicationRecord.transaction do
          locked_users = User.where(id: user_ids).order(:id).lock.to_a
          unless locked_users.map(&:id) == user_ids
            raise ActiveRecord::RecordNotFound, "identity_user_mutation_participant_missing"
          end

          yield locked_users.index_by(&:id)
        end
      end

      private

      def normalized_user_ids(users)
        participants = Array(users).flatten
        raise ArgumentError, "identity_user_mutation_participants_required" if participants.empty?

        participants.map do |participant|
          raw_id = participant.respond_to?(:id) ? participant.id : participant
          user_id = Integer(raw_id, exception: false)
          unless user_id&.positive?
            raise ArgumentError, "identity_user_mutation_participant_invalid"
          end

          user_id
        end.uniq.sort
      end
    end
  end
end
