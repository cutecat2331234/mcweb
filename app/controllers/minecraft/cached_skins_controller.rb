# frozen_string_literal: true

module Minecraft
  class CachedSkinsController < ApplicationController
    skip_before_action :require_login, raise: false

    ATTACHMENTS = {
      "avatar" => :skin_avatar_file,
      "bust" => :skin_bust_file,
      "full" => :skin_full_file,
      "skin" => :skin_texture_file,
      "cape" => :cape_texture_file
    }.freeze

    def show
      attachment_name = ATTACHMENTS.fetch(params[:variant])
      identity = Minecraft::PlayerIdentity.active.bound.find_by(id: params[:id])
      return unavailable_variant unless identity

      attachment = identity.public_send(attachment_name)
      return unavailable_variant unless attachment.attached?

      expires_in 1.day, public: true
      fresh_when(etag: attachment.blob.checksum, public: true)
      return if performed?

      redirect_to rails_blob_path(attachment, disposition: "inline")
    rescue KeyError
      head :not_found
    end

    private

    def unavailable_variant
      return redirect_to("/minecraft/default-skin-avatar.png") if params[:variant] == "avatar"

      head :not_found
    end
  end
end
