# frozen_string_literal: true

module Community
  class SyncSectionModerators < ApplicationService
    def initialize(section:, usernames:)
      @section = section
      @usernames = Array(usernames).flat_map { |raw| raw.to_s.split(/[,\n]+/) }.map(&:strip).reject(&:blank?).uniq
    end

    def call
      users = User.where(username: @usernames).index_by(&:username)
      missing = @usernames - users.keys
      return ServiceResult.failure(error: I18n.t("mcweb.forum.sync_section_moderators.users_missing", users: missing.join(I18n.t("mcweb.commerce.list_separator")))) if missing.any?

      Community::SectionModerator.transaction do
        @section.section_moderators.where.not(user_id: users.values.map(&:id)).destroy_all
        users.each_value do |user|
          @section.section_moderators.find_or_create_by!(user: user)
        end
      end

      ServiceResult.success(users.values)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
