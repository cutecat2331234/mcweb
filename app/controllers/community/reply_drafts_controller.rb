# frozen_string_literal: true

module Community
  class ReplyDraftsController < ApplicationController
    include Community::TopicVisibility

    before_action :require_login
    before_action :set_topic

    def update
      result = Community::SaveReplyDraft.call(
        user: current_user,
        topic: @topic,
        body: reply_draft_params[:body],
        attachment_ids: reply_draft_params[:attachment_ids]
      )

      if result.success?
        head :no_content
      else
        render json: { error: service_error_message(result) }, status: :unprocessable_entity
      end
    end

    def destroy
      Community::ReplyDraft.where(user: current_user, topic: @topic).delete_all
      head :no_content
    end

    private

    def set_topic
      @topic = Community::Topic.find_by!(public_id: params[:topic_id])
      ensure_topic_visible!(@topic)
    end

    def reply_draft_params
      {
        body: params[:body],
        attachment_ids: params[:attachment_ids]
      }
    end
  end
end
