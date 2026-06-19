# frozen_string_literal: true

module Commerce
  class ProductQuestionsController < ApplicationController
    before_action :require_login, only: %i[create answer toggle_answer_helpful]
    before_action :set_product

    def index
      questions = @product.questions.visible.includes(:user, :answers).recent.limit(50)

      render json: { questions: questions.map { |q| serialize_question(q) } }
    end

    def create
      order_item = nil
      if params[:order_item_id].present?
        order_item = Commerce::OrderItem.joins(:order)
          .where(store_orders: { user_id: current_user.id })
          .find_by(id: params[:order_item_id])
      end

      result = Commerce::CreateProductQuestion.call(
        user: current_user,
        product: @product,
        body: params.dig(:question, :body),
        order_item: order_item
      )

      if result.success?
        if params[:return_order_id].present?
          order = Commerce::Order.find_by(public_id: params[:return_order_id], user_id: current_user.id)
          return redirect_to store_order_path(order), notice: t("mcweb.flash.question_submitted") if order
        end
        redirect_to store_product_path(@product), notice: t("mcweb.flash.question_submitted")
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    def answer
      question = @product.questions.visible.find(params[:question_id])
      official = current_user.permission?("store.questions.answer") || current_user.permission?("admin.access")

      result = Commerce::AnswerProductQuestion.call(
        user: current_user,
        question: question,
        body: params.dig(:answer, :body),
        official: official
      )

      if result.success?
        redirect_to store_product_path(@product), notice: t("mcweb.flash.answer_published")
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    def toggle_answer_helpful
      question = @product.questions.visible.find(params[:question_id])
      answer = question.answers.find(params[:answer_id])
      result = Commerce::ToggleAnswerHelpful.call(user: current_user, answer: answer)

      if result.success?
        redirect_to store_product_path(@product), notice: result.value[:helpful] ? t("mcweb.flash.helpful_marked") : t("mcweb.flash.helpful_unmarked")
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    private

    def set_product
      @product = Commerce::Product.available.find_by!(public_id: params[:product_id])
    end

    def serialize_question(question)
      {
        id: question.id,
        body: question.body,
        author: question.user.username,
        created_at: l(question.created_at, format: :short),
        answers: question.answers.order(created_at: :asc).map do |answer|
          {
            id: answer.id,
            body: answer.body,
            author: answer.user.username,
            official: answer.official,
            created_at: l(answer.created_at, format: :short)
          }
        end
      }
    end
  end
end
