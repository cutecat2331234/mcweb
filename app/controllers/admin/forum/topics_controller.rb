# frozen_string_literal: true

module Admin
  module Forum
    class TopicsController < BaseController
      before_action -> { require_permission("forum.topics.lock") }
      before_action :set_topic, only: %i[show edit update destroy]

      def index
        scope = ::Community::Topic.includes(:user, :section).order(last_posted_at: :desc)
        @pagy, topics = pagy(scope, limit: 30)

        render inertia: "Admin/Generic/Index", props: {
          title: "论坛主题",
          columns: [
            admin_column(:title, "标题", link: true),
            admin_column(:author, "作者"),
            admin_column(:section, "分区"),
            admin_column(:status, "状态"),
            admin_column(:locked, "锁定"),
            admin_column(:archived, "归档"),
            admin_column(:replies, "回复")
          ],
          rows: topics.map do |topic|
            admin_row(
              title: topic.title,
              author: topic.user&.username,
              section: topic.section&.name,
              status: topic.status,
              locked: topic.locked? ? "是" : "否",
              archived: topic.archived_at.present? ? "是" : "否",
              replies: topic.replies_count.to_s,
              url: admin_forum_topic_path(topic),
              publicId: topic.public_id
            )
          end,
          pagination: pagy_props(@pagy),
          selectable: true,
          bulkModerateUrl: bulk_moderate_forum_topics_path
        }
      end

      def show
        posts = @topic.posts.chronological.includes(:user)

        render inertia: "Admin/Generic/Show", props: {
          title: @topic.title,
          subtitle: @topic.user&.username,
          fields: [
            { label: "状态", value: @topic.status },
            { label: "置顶", value: @topic.pinned? ? "是" : "否" },
            { label: "锁定", value: @topic.locked? ? "是" : "否" },
            { label: "回复数", value: @topic.replies_count.to_s }
          ],
          sections: [
            {
              title: "帖子",
              items: posts.map do |post|
                { label: "##{post.floor_number} #{post.user.username}", value: post.body.truncate(120) }
              end
            }
          ],
          backUrl: admin_forum_topics_path
        }
      end

      def edit
      end

      def update
        if @topic.update(topic_params)
          redirect_to admin_forum_topic_path(@topic), notice: t("mcweb.flash.topic_updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @topic.soft_delete!
        redirect_to admin_forum_topics_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.topic"))
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
