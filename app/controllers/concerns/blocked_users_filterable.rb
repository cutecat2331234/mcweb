# frozen_string_literal: true

module BlockedUsersFilterable
  extend ActiveSupport::Concern

  private

  def blocked_user_ids
    return [] unless logged_in?

    Community::UserBlock.blocked_user_ids(current_user)
  end

  def filter_blocked_topics(scope)
    ids = blocked_user_ids
    return scope if ids.empty?

    scope.where.not(user_id: ids)
  end

  def filter_blocked_posts(scope)
    ids = blocked_user_ids
    return scope if ids.empty?

    scope.where.not(user_id: ids)
  end
end
