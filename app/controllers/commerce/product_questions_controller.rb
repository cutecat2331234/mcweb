# frozen_string_literal: true

module Commerce
  class ProductQuestionsController < ApplicationController
    before_action :require_login, except: :index
    before_action :set_visible_product, only: %i[index create answer toggle_answer_helpful]
    before_action :set_mutation_product, only: %i[update destroy update_answer destroy_answer]
    before_action :set_question, only: %i[answer update_answer destroy_answer toggle_answer_helpful]
    before_action :set_owned_question, only: %i[update destroy]
    before_action :set_answer, only: :toggle_answer_helpful
    before_action :set_owned_answer, only: %i[update_answer destroy_answer]

    def index
      questions = @product.questions.visible.includes(:user, visible_answers: :user).recent.limit(50)

      render json: { questions: questions.map { |question| serialize_question(question) } }
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

    def update
      result = Commerce::UpdateProductQuestion.call(
        user: current_user,
        question: @question,
        body: params.dig(:question, :body),
        expected_version: params.dig(:question, :expected_version)
      )
      redirect_with_result(result, success_key: "mcweb.flash.question_updated")
    end

    def destroy
      result = Commerce::DeleteProductQuestion.call(user: current_user, question: @question)
      redirect_with_result(result, success_key: "mcweb.flash.question_deleted")
    end

    def answer
      result = Commerce::AnswerProductQuestion.call(
        user: current_user,
        question: @question,
        body: params.dig(:answer, :body),
        official: official_answer_permission?
      )
      redirect_with_result(result, success_key: "mcweb.flash.answer_published")
    end

    def update_answer
      result = Commerce::UpdateProductAnswer.call(
        user: current_user,
        answer: @answer,
        body: params.dig(:answer, :body),
        expected_version: params.dig(:answer, :expected_version)
      )
      redirect_with_result(result, success_key: "mcweb.flash.answer_updated")
    end

    def destroy_answer
      result = Commerce::DeleteProductAnswer.call(user: current_user, answer: @answer)
      redirect_with_result(result, success_key: "mcweb.flash.answer_deleted")
    end

    def toggle_answer_helpful
      result = Commerce::ToggleAnswerHelpful.call(user: current_user, answer: @answer)

      if result.success?
        notice = result.value[:helpful] ? t("mcweb.flash.helpful_marked") : t("mcweb.flash.helpful_unmarked")
        redirect_to store_product_path(@product), notice: notice
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    private

    def set_visible_product
      @product = Commerce::Product.available.find_by!(public_id: params[:product_id])
      raise ActiveRecord::RecordNotFound unless Commerce::StoreFeatures.product_visible?(@product)
    end

    def set_mutation_product
      @product = Commerce::Product.find_by!(public_id: params[:product_id])
    end

    def set_question
      @question = @product.questions.find(params[:question_id])
    end

    def set_owned_question
      @question = @product.questions.where(user: current_user).find(params[:question_id])
    end

    def set_answer
      @answer = @question.answers.find(params[:answer_id])
    end

    def set_owned_answer
      @answer = @question.answers.where(user: current_user).find(params[:answer_id])
    end

    def official_answer_permission?
      current_user.permission?("store.questions.answer") || current_user.permission?("admin.access")
    end

    def redirect_with_result(result, success_key:)
      destination = product_return_path
      if result.success?
        redirect_to destination, notice: t(success_key)
      else
        redirect_to destination, alert: service_error_message(result)
      end
    end

    def product_return_path
      if Commerce::Product.available.where(id: @product.id).exists? &&
          Commerce::StoreFeatures.product_visible?(@product)
        store_product_path(@product)
      else
        store_products_path
      end
    end

    def serialize_question(question)
      {
        id: question.id,
        lock_version: question.lock_version,
        body: question.body,
        author: question.user.username,
        created_at: l(question.created_at, format: :short),
        answers: question.visible_answers.sort_by(&:created_at).map do |answer|
          {
            id: answer.id,
            lock_version: answer.lock_version,
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
