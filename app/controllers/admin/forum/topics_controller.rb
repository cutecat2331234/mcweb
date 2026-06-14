# frozen_string_literal: true

module Admin
  module Forum
    class TopicsController < BaseController
      before_action -> { require_permission("admin.forum.moderate") }
      before_action :set_topic, only: %i[show edit update destroy]

      def index
        @topics = ::Community::Topic.order(last_posted_at: :desc).limit(50)
      end

      def show
        @posts = @topic.posts.chronological.includes(:user)
      end

      def edit
      end

      def update
        if @topic.update(topic_params)
          redirect_to admin_forum_topic_path(@topic), notice: "Topic updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @topic.soft_delete!
        redirect_to admin_forum_topics_path, notice: "Topic deleted."
      end

      private

      def set_topic
        @topic = ::Community::Topic.find_by!(public_id: params[:id])
      end

      def topic_params
        params.expect(topic: %i[title status pinned locked])[:topic]
      end
    end
  end
end
