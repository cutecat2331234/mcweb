# frozen_string_literal: true

module Minecraft
  class PlayerIdentity < ApplicationRecord
    DEFAULT_SKIN_REFRESH_INTERVAL = 24.hours
    REQUIRED_SKIN_CACHE_ATTACHMENTS = %w[
      skin_texture_file
      skin_avatar_file
      skin_bust_file
      skin_full_file
    ].freeze

    belongs_to :player_profile, class_name: "Minecraft::PlayerProfile"
    belongs_to :primary_server, class_name: "Minecraft::Server", optional: true
    has_one_attached :skin_texture_file
    has_one_attached :cape_texture_file
    has_one_attached :skin_avatar_file
    has_one_attached :skin_bust_file
    has_one_attached :skin_full_file
    has_many :skin_refresh_requests,
             class_name: "Minecraft::SkinRefreshRequest",
             foreign_key: :player_identity_id,
             dependent: :delete_all

    validates :platform, :external_uuid, :username, :identity_type, :valid_from, presence: true
    validates :external_uuid, uniqueness: { scope: :platform, conditions: -> { where(superseded_at: nil) } }

    scope :active, -> { where(superseded_at: nil) }
    scope :bound, lambda {
      joins(player_profile: :identity_links)
        .merge(Minecraft::IdentityLink.active)
        .distinct
    }
    scope :skin_cache_due, lambda { |at: Time.current, interval: DEFAULT_SKIN_REFRESH_INTERVAL|
      due = where("skin_cached_at IS NULL OR skin_cached_at <= ?", at - interval)
      REQUIRED_SKIN_CACHE_ATTACHMENTS.reduce(due) do |relation, attachment_name|
        attached_identity_ids = ActiveStorage::Attachment
          .where(record_type: polymorphic_name, name: attachment_name)
          .select(:record_id)
        relation.or(where.not(id: attached_identity_ids))
      end
    }

    def supersede!
      update!(superseded_at: Time.current)
    end

    def skin_cached?
      skin_cached_at.present? &&
        skin_texture_file.attached? &&
        skin_avatar_file.attached? &&
        skin_bust_file.attached? &&
        skin_full_file.attached?
    end

    def skin_cache_stale?(at: Time.current, interval: DEFAULT_SKIN_REFRESH_INTERVAL)
      !skin_cached? || skin_cached_at <= at - interval
    end
  end
end
