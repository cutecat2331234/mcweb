# frozen_string_literal: true

module Admin
  module Forum
    class CannedResponsesController < BaseController
      before_action -> { require_permission("forum.topics.lock") }
      before_action :set_response, only: %i[edit update destroy]

      def index
        responses = ::Community::CannedResponse.ordered.includes(:author)

        render inertia: "Admin/Generic/Index", props: {
          title: "罐头回复",
          columns: [
            admin_column(:title, "标题", link: true),
            admin_column(:author, "作者")
          ],
          rows: responses.map do |response|
            admin_row(
              title: response.title,
              author: response.author.username,
              url: edit_admin_forum_canned_response_path(response)
            )
          end,
          actions: [{ label: "新建罐头回复", href: new_admin_forum_canned_response_path }]
        }
      end

      def new
        render inertia: "Admin/Forum/CannedResponses/Form", props: form_props(::Community::CannedResponse.new)
      end

      def create
        response = ::Community::CannedResponse.new(canned_response_params)
        response.author = current_user
        if response.save
          redirect_to admin_forum_canned_responses_path, notice: "罐头回复已创建。"
        else
          render inertia: "Admin/Forum/CannedResponses/Form", props: form_props(response), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/CannedResponses/Form", props: form_props(@response, editing: true)
      end

      def update
        if @response.update(canned_response_params)
          redirect_to admin_forum_canned_responses_path, notice: "罐头回复已更新。"
        else
          render inertia: "Admin/Forum/CannedResponses/Form", props: form_props(@response, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @response.destroy!
        redirect_to admin_forum_canned_responses_path, notice: "罐头回复已删除。"
      end

      private

      def set_response
        @response = ::Community::CannedResponse.find(params[:id])
      end

      def canned_response_params
        params.require(:canned_response).permit(:title, :body)
      end

      def form_props(response, editing: false)
        {
          title: editing ? "编辑罐头回复" : "新建罐头回复",
          canned_response: {
            title: response.title || "",
            body: response.body || ""
          },
          submitUrl: editing ? admin_forum_canned_response_path(response) : admin_forum_canned_responses_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_canned_responses_path,
          deleteUrl: editing ? admin_forum_canned_response_path(response) : nil
        }
      end
    end
  end
end
