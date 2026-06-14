# frozen_string_literal: true

module Community
  class DraftsController < ApplicationController
    before_action :require_login

    def index
      drafts = Community::Topic
        .where(user: current_user, status: :draft)
        .includes(:section, :posts)
        .order(updated_at: :desc)

      render inertia: "Community/Drafts/Index", props: {
        drafts: drafts.map do |draft|
          body = draft.posts.first&.body.to_s
          formatted = Community::FormatPostBody.call(body: body)
          {
            id: draft.public_id,
            title: draft.title,
            body_excerpt: body.truncate(120),
            preview_html: formatted.success? ? formatted.value : nil,
            section_name: draft.section.name,
            section_url: forum_section_path(draft.section),
            updated_at: l(draft.updated_at, format: :short),
            scheduled_at: draft.scheduled_at ? l(draft.scheduled_at, format: :short) : nil,
            edit_url: edit_forum_draft_path(draft)
          }
        end
      }
    end

    def edit
      draft = current_user_draft
      render inertia: "Community/Drafts/Edit", props: {
        draft: {
          id: draft.public_id,
          title: draft.title,
          body: draft.posts.first&.body || "",
          tags: draft.tags.map(&:name).join(", "),
          scheduled_at_input: draft.scheduled_at&.strftime("%Y-%m-%dT%H:%M"),
          section: { name: draft.section.name, slug: draft.section.slug }
        }
      }
    end

    def create
      section = Community::Section.find_by!(slug: params[:section_id])
      result = Community::SaveTopicDraft.call(
        user: current_user,
        section: section,
        title: draft_params[:title],
        body: draft_params[:body],
        tag_names: draft_params[:tags],
        prefix: draft_params[:prefix],
        scheduled_at: draft_params[:scheduled_at],
        poll_question: draft_params[:poll_question],
        poll_options: draft_params[:poll_options],
        poll_closes_days: draft_params[:poll_closes_days],
        poll_multiple_choice: draft_params[:poll_multiple_choice],
        poll_max_choices: draft_params[:poll_max_choices],
        poll_hide_results_until_vote: draft_params[:poll_hide_results_until_vote]
      )

      if result.success?
        redirect_to forum_drafts_path, notice: "草稿已保存。"
      else
        redirect_to new_forum_topic_path(section_id: section.slug), alert: service_error_message(result)
      end
    end

    def update
      draft = current_user_draft
      result = Community::SaveTopicDraft.call(
        user: current_user,
        section: draft.section,
        title: draft_params[:title],
        body: draft_params[:body],
        tag_names: draft_params[:tags],
        topic: draft,
        scheduled_at: draft_params[:scheduled_at],
        clear_schedule: draft_params[:clear_schedule]
      )

      if result.success?
        redirect_to forum_drafts_path, notice: "草稿已更新。"
      else
        redirect_to edit_forum_draft_path(draft), alert: service_error_message(result)
      end
    end

    def publish
      draft = current_user_draft
      result = Community::PublishTopicDraft.call(user: current_user, topic: draft)

      if result.success?
        redirect_to forum_topic_path(draft), notice: "主题已发布。"
      else
        redirect_to edit_forum_draft_path(draft), alert: service_error_message(result)
      end
    end

    def destroy
      draft = current_user_draft
      draft.soft_delete!
      redirect_to forum_drafts_path, notice: "草稿已删除。"
    end

    private

    def current_user_draft
      Community::Topic.find_by!(public_id: params[:id], user: current_user, status: :draft)
    end

    def draft_params
      params.require(:draft).permit(
        :title, :body, :tags, :scheduled_at, :clear_schedule, :prefix,
        :poll_question, :poll_options, :poll_closes_days,
        :poll_multiple_choice, :poll_max_choices, :poll_hide_results_until_vote
      )
    end
  end
end
