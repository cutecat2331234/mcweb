# frozen_string_literal: true

module BlockedUsersFilterable
  extend ActiveSupport::Concern

  private

  def filter_blocked_topics(scope)
    return scope unless logged_in?

    blocked_ids = Community::UserBlock.blocked_user_ids(current_user)
    return scope if blocked_ids.empty?

    scope.where.not(user_id: blocked_ids)
  end
end
