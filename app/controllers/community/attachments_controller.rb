# frozen_string_literal: true

module Community
  class AttachmentsController < ApplicationController
    before_action :require_login, only: :create
    before_action :rate_limit_upload!, only: :create
    before_action :set_attachment, only: :show

    def create
      result = Community::CreatePostAttachment.call(user: current_user, file: params[:file])
      if result.success?
        attachment = result.value
        render json: serialize_attachment(attachment)
      else
        render json: { error: service_error_message(result) }, status: :unprocessable_entity
      end
    end

    def show
      return head :forbidden unless Community::PostAttachmentAccess.downloadable?(@attachment, user: current_user)

      @attachment.increment!(:download_count)
      redirect_to rails_blob_path(@attachment.file, disposition: "attachment", only_path: true), allow_other_host: false
    end

    private

    def set_attachment
      @attachment = Community::PostAttachment.find(params[:id])
    end

    def serialize_attachment(attachment)
      {
        id: attachment.id,
        filename: attachment.filename,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        human_size: attachment.human_size,
        download_url: forum_attachment_path(attachment)
      }
    end

    def rate_limit_upload!
      result = Administration::RateLimiter.call(
        key: "forum_attachment:#{current_user.id}",
        limit: 30,
        window: 1.hour
      )
      return unless result.failure?

      render json: { error: t("mcweb.flash.rate_limited") }, status: :too_many_requests
    end
  end
end
