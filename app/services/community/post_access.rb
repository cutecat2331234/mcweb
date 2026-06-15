# frozen_string_literal: true

module Community
  module PostAccess
    module_function

    def readable?(post:, user:)
      return false unless PollParticipation.visible?(topic: post.topic, user: user)
      return true if user&.permission?("forum.topics.lock")
      return true if post.status == "published"

      false
    end

    def editable?(post:, user:)
      return false unless PollParticipation.visible?(topic: post.topic, user: user)
      return true if user&.permission?("forum.topics.lock")
      return true if post.status == "published"
      return true if post.status == "hidden" && user&.id == post.user_id

      false
    end
  end
end
