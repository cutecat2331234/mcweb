# frozen_string_literal: true

module Commerce
  class ProductQuestionsController < ApplicationController
    before_action :require_login, only: %i[create answer]
    before_action :set_product

    def index
      questions = @product.questions.visible.includes(:user, :answers).recent.limit(50)

      render json: { questions: questions.map { |q| serialize_question(q) } }
    end

    def create
      result = Commerce::CreateProductQuestion.call(
        user: current_user,
        product: @product,
        body: params.dig(:question, :body)
      )

      if result.success?
        redirect_to store_product_path(@product), notice: "问题已提交。"
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
        redirect_to store_product_path(@product), notice: "回答已发布。"
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
