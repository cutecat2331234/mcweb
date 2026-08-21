# frozen_string_literal: true

class AccountController < ApplicationController
  before_action :require_login
  after_action :set_private_no_store

  def show
    forum_enabled = FeatureFlags.enabled?(:forum)
    minecraft_enabled = FeatureFlags.enabled?(:minecraft)

    render inertia: "Account/Show", props: {
      identity: identity_props,
      security: security_props,
      activity: activity_props(forum_enabled),
      minecraft: minecraft_props(minecraft_enabled),
      forum_enabled: forum_enabled,
      minecraft_enabled: minecraft_enabled
    }
  end

  private

  def identity_props
    {
      avatar_url: current_user.avatar_url(size: 96),
      display_name: current_user.display_name,
      username: current_user.username,
      email: current_user.email,
      locale: current_user.locale,
      joined_at: current_user.created_at.iso8601
    }
  end

  def security_props
    {
      email_verified: current_user.email_verified?,
      totp_enabled: current_user.totp_enabled?,
      require_totp: current_user.require_totp?,
      active_sessions_count: current_user.sessions.active.count
    }
  end

  def activity_props(forum_enabled)
    return nil unless forum_enabled

    {
      unread_notifications: current_user.notifications.unread.count,
      unread_messages: Community::Conversation.total_unread_count_for(current_user),
      topic_drafts: Community::Topic.where(user: current_user, status: :draft).count
    }
  end

  def minecraft_props(minecraft_enabled)
    return nil unless minecraft_enabled

    link = Minecraft::IdentityLink.primary
      .where(user: current_user)
      .includes(player_profile: :player_identities)
      .first
    return { bound: false } unless link

    identity = link.player_profile.active_identity
    {
      bound: true,
      username: identity&.username,
      uuid: identity&.external_uuid
    }
  end

  def set_private_no_store
    response.set_header("Cache-Control", "private, no-store")
  end
end
