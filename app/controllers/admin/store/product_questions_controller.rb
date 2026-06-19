# frozen_string_literal: true

module Admin
  module Store
    class ProductQuestionsController < BaseController
      before_action -> { require_permission("store.questions.manage") }
      before_action :set_question, only: %i[hide unhide destroy]

      def index
        questions = Commerce::ProductQuestion.includes(:user, :product, :order_item, answers: :user, order_item: :order).order(created_at: :desc).limit(100)

        render inertia: "Admin/Store/ProductQuestions/Index", props: {
          questions: questions.map do |q|
            {
              id: q.id,
              product: q.product.name,
              author: q.user.username,
              body: q.body,
              status: q.status,
              created_at: l(q.created_at, format: :short),
              order_number: q.order_item&.order&.order_number,
              hide_url: hide_admin_store_product_question_path(q),
              unhide_url: unhide_admin_store_product_question_path(q)
            }
          end
        }
      end

      def hide
        result = Commerce::HideProductQuestion.call(question: @question)
        if result.success?
          redirect_to admin_store_product_questions_path, notice: t("mcweb.flash.question_hidden")
        else
          redirect_to admin_store_product_questions_path, alert: service_error_message(result)
        end
      end

      def unhide
        result = Commerce::ShowProductQuestion.call(question: @question)
        if result.success?
          redirect_to admin_store_product_questions_path, notice: t("mcweb.flash.question_restored")
        else
          redirect_to admin_store_product_questions_path, alert: service_error_message(result)
        end
      end

      def destroy
        @question.destroy!
        redirect_to admin_store_product_questions_path, notice: t("mcweb.flash.question_deleted")
      end

      private

      def set_question
        @question = Commerce::ProductQuestion.find(params[:id])
      end
    end
  end
end
