# frozen_string_literal: true

module Community
  class ConversationMembershipLock
    class ParticipantSetChanged < StandardError; end

    MAX_ATTEMPTS = 3

    def self.with(conversation:, users:)
      attempts = 0

      begin
        participant_ids = conversation.participants.reorder(:user_id).pluck(:user_id)
        lock_user_ids = (participant_ids + Array(users).map { |user| user.respond_to?(:id) ? user.id : user }).compact.uniq
        participant_set_changed = false
        value = Identity::UserMutationLock.with_users(users: lock_user_ids) do
          conversation.with_lock do
            current_participant_ids = conversation.participants.reorder(:user_id).pluck(:user_id)
            if current_participant_ids != participant_ids
              participant_set_changed = true
              next
            end

            yield
          end
        end
        raise ParticipantSetChanged if participant_set_changed

        value
      rescue ParticipantSetChanged
        attempts += 1
        retry if attempts < MAX_ATTEMPTS

        raise
      end
    end

    private_class_method :new
  end
end
