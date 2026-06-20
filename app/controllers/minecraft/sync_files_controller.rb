# frozen_string_literal: true

module Minecraft
  class SyncFilesController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def show
      verifier = Rails.application.message_verifier("minecraft.sync_files")
      data = verifier.verify(params[:token])
      return head :gone if data["exp"].to_i < Time.current.to_i

      full = Minecraft::SyncFilePath.resolve(data["path"])
      return head :not_found unless full

      send_file full, disposition: "attachment", filename: full.basename.to_s
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      head :forbidden
    end
  end
end
