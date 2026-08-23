# frozen_string_literal: true

module Community
  class ExpireConversationInvitationsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Community::CloseStaleConversationInvitations.call
    end
  end
end
