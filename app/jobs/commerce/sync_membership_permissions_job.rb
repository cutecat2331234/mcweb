# frozen_string_literal: true

module Commerce
  class SyncMembershipPermissionsJob < ApplicationJob
    queue_as :minecraft

    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user

      Commerce::SyncMembershipGamePermissions.call(user: user)
    end
  end
end
