# frozen_string_literal: true

module Admin
  module Store
    class ProductQuestionsController < BaseController
      before_action -> { require_permission("store.questions.manage") }
      before_action :set_question, only: %i[hide unhide destroy hide_answer unhide_answer]
      before_action :set_answer, only: %i[hide_answer unhide_answer]

      def index
        questions = Commerce::ProductQuestion.includes(:user, :product, :order_item, answers: :user, order_item: :order).order(created_at: :desc).limit(100)

        render inertia: "Admin/Store/ProductQuestions/Index", props: {
          questions: questions.map do |q|
            {
              id: q.id,
              product: q.product.name,
              author: q.user.username,
              body: q.body,
              status: product_question_status_label(q.status),
              created_at: l(q.created_at, format: :short),
              order_number: q.order_item&.order&.order_number,
              hide_url: hide_admin_store_product_question_path(q),
              unhide_url: unhide_admin_store_product_question_path(q),
              status_key: q.status,
              answers: q.answers.sort_by(&:created_at).map do |answer|
                {
                  id: answer.id,
                  author: answer.user.username,
                  body: answer.body,
                  official: answer.official?,
                  status: product_answer_status_label(answer.status),
                  status_key: answer.status,
                  hide_url: hide_answer_admin_store_product_question_path(q, answer_id: answer.id),
                  unhide_url: unhide_answer_admin_store_product_question_path(q, answer_id: answer.id)
                }
              end
            }
          end
        }
      end

      def hide
        result = Commerce::HideProductQuestion.call(question: @question, actor: current_user)
        if result.success?
          redirect_to admin_store_product_questions_path, notice: t("mcweb.flash.question_hidden")
        else
          redirect_to admin_store_product_questions_path, alert: service_error_message(result)
        end
      end

      def unhide
        result = Commerce::ShowProductQuestion.call(question: @question, actor: current_user)
        if result.success?
          redirect_to admin_store_product_questions_path, notice: t("mcweb.flash.question_restored")
        else
          redirect_to admin_store_product_questions_path, alert: service_error_message(result)
        end
      end

      def destroy
        result = Commerce::HideProductQuestion.call(question: @question, actor: current_user)
        if result.success?
          redirect_to admin_store_product_questions_path, notice: t("mcweb.flash.question_hidden")
        else
          redirect_to admin_store_product_questions_path, alert: service_error_message(result)
        end
      end

      def hide_answer
        result = Commerce::HideProductAnswer.call(answer: @answer, actor: current_user)
        if result.success?
          redirect_to admin_store_product_questions_path, notice: t("mcweb.flash.answer_hidden")
        else
          redirect_to admin_store_product_questions_path, alert: service_error_message(result)
        end
      end

      def unhide_answer
        result = Commerce::ShowProductAnswer.call(answer: @answer, actor: current_user)
        if result.success?
          redirect_to admin_store_product_questions_path, notice: t("mcweb.flash.answer_restored")
        else
          redirect_to admin_store_product_questions_path, alert: service_error_message(result)
        end
      end

      private

      def set_question
        @question = Commerce::ProductQuestion.find(params[:id])
      end

      def set_answer
        @answer = @question.answers.find(params[:answer_id])
      end

      def product_question_status_label(status)
        t("mcweb.labels.product_question_status.#{status}", default: status.to_s.humanize)
      end

      def product_answer_status_label(status)
        t("mcweb.labels.product_answer_status.#{status}", default: status.to_s.humanize)
      end
    end
  end
end
