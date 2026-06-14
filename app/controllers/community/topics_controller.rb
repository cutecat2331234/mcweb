# frozen_string_literal: true

module Community
  class TopicsController < ApplicationController
    before_action :require_login, only: %i[new create edit update]
    before_action :set_section, only: %i[index new create]
    before_action :set_topic, only: %i[show edit update]

    def index
      @topics = @section.topics.pinned_first.limit(50)
    end

    def show
      @topic.record_view!
      @posts = @topic.posts.chronological.includes(:user)
    end

    def new
      @topic = @section.topics.build
    end

    def create
      result = Community::CreateTopic.call(
        user: current_user,
        section: @section,
        title: topic_params[:title],
        ip_address: request.remote_ip
      )

      if result.success?
        redirect_to forum_topic_path(result.value), notice: "Topic created."
      else
        @topic = @section.topics.build(topic_params)
        flash.now[:alert] = service_error_message(result)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize_topic_owner!
    end

    def update
      authorize_topic_owner!

      if @topic.update(topic_params)
        redirect_to forum_topic_path(@topic), notice: "Topic updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_section
      @section = Community::Section.find_by!(slug: params[:section_id])
    end

    def set_topic
      @topic = Community::Topic.find_by!(public_id: params[:id])
    end

    def topic_params
      params.require(:topic).permit(:title)
    end

    def authorize_topic_owner!
      return if current_user&.id == @topic.user_id || current_user&.permission?("forum.topics.lock")

      redirect_to forum_topic_path(@topic), alert: "You are not authorized to edit this topic."
    end
  end
end
