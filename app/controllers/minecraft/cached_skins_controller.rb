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
      return unavailable_variant(identity:) unless attachment.attached?

      serve_attachment(attachment, max_age: 1.day)
    rescue KeyError
      head :not_found
    end

    private

    def serve_attachment(attachment, max_age:)
      expires_in max_age, public: true
      fresh_when(etag: attachment.blob.checksum, public: true)
      return if performed?

      redirect_to rails_blob_path(attachment, disposition: "inline")
    end

    def unavailable_variant(identity: nil)
      return redirect_to("/minecraft/default-skin-avatar.png") if params[:variant] == "avatar"
      if params[:variant] == "bust" && identity&.skin_avatar_file&.attached?
        return serve_attachment(identity.skin_avatar_file, max_age: 5.minutes)
      end

      head :not_found
    end
  end
end
