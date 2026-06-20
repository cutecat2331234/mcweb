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
          title: forum_t("topics.title"),
          columns: [
            admin_column(:title, forum_t("topics.col_title"), link: true),
            admin_column(:author, forum_t("topics.col_author")),
            admin_column(:section, forum_t("topics.col_section")),
            admin_column(:status, forum_t("topics.col_status")),
            admin_column(:locked, forum_t("topics.col_locked")),
            admin_column(:archived, forum_t("topics.col_archived")),
            admin_column(:replies, forum_t("topics.col_replies"))
          ],
          rows: topics.map do |topic|
            admin_row(
              title: topic.title,
              author: topic.user&.username,
              section: topic.section&.name,
              status: topic.status,
              locked: forum_yes_no(topic.locked?),
              archived: forum_yes_no(topic.archived_at.present?),
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
            { label: forum_t("topics.col_status"), value: @topic.status },
            { label: forum_t("topics.field_pinned"), value: forum_yes_no(@topic.pinned?) },
            { label: forum_t("topics.col_locked"), value: forum_yes_no(@topic.locked?) },
            { label: forum_t("topics.field_replies"), value: @topic.replies_count.to_s }
          ],
          sections: [
            {
              title: forum_t("topics.section_posts"),
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
        @topic = ::Community::Topic.find(params[:id])
      end

      def topic_params
        params.require(:topic).permit(:title, :status, :locked, :pinned)
      end
    end
  end
end
