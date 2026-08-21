# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class CommerceSelfServiceRoutesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @other_user = create_user
    @product = create_product("first")
    @other_product = create_product("second")
    @question = Commerce::ProductQuestion.create!(
      user: @owner,
      product: @product,
      body: "Question",
      status: :published
    )
    @answer = Commerce::ProductAnswer.create!(
      user: @owner,
      question: @question,
      body: "Answer",
      status: :published
    )
  end

  test "customer orders collection has no parallel create route" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/app/store/orders", method: :post)
    end
  end

  test "question and answer identifiers are scoped to the product in the URL" do
    sign_in_as(@owner)

    patch store_product_update_question_path(@other_product, question_id: @question.id),
      params: { question: { body: "Cross-product edit" } }
    assert_response :not_found

    patch store_product_update_answer_path(
      @other_product,
      question_id: @question.id,
      answer_id: @answer.id
    ), params: { answer: { body: "Cross-product answer edit" } }
    assert_response :not_found

    assert_equal "Question", @question.reload.body
    assert_equal "Answer", @answer.reload.body
  end

  test "owner edit routes bind product question answer and review identifiers independently" do
    review = Commerce::Review.create!(
      user: @owner,
      product: @product,
      rating: 5,
      body: "Original review",
      status: :published
    )
    sign_in_as(@owner)

    patch store_product_update_question_path(@product, question_id: @question.id),
      params: { question: { body: "Edited question" } }
    assert_redirected_to store_product_path(@product)

    patch store_product_update_answer_path(
      @product,
      question_id: @question.id,
      answer_id: @answer.id
    ), params: { answer: { body: "Edited answer" } }
    assert_redirected_to store_product_path(@product)

    patch store_product_review_path(@product, review),
      params: { review: { rating: 4, body: "Edited review", retained_photo_ids: [] } }
    assert_redirected_to store_product_path(@product)
    assert_nil flash[:alert], flash[:alert]

    assert_equal "Edited question", @question.reload.body
    assert_equal "Edited answer", @answer.reload.body
    assert_equal [ 4, "Edited review" ], review.reload.values_at(:rating, :body)
  end

  test "product page renders visible question and answer actions with nested route parameters" do
    review = Commerce::Review.create!(
      user: @owner,
      product: @product,
      rating: 5,
      body: "Visible review",
      status: :published
    )
    sign_in_as(@owner)

    get store_product_path(@product)

    assert_response :success
    question = inertia.props.deep_symbolize_keys.fetch(:questions).find { |entry| entry[:id] == @question.id }
    answer = question.fetch(:answers).find { |entry| entry[:id] == @answer.id }
    assert_equal store_product_update_question_path(@product, question_id: @question.id), question.fetch(:updateUrl)
    assert_equal store_product_update_answer_path(
      @product,
      question_id: @question.id,
      answer_id: @answer.id
    ), answer.fetch(:update_url)
    assert_equal store_product_review_path(@product, review),
      inertia.props.deep_symbolize_keys.fetch(:updateReviewUrl)
  end

  test "refund withdrawal route cannot enumerate another customer's order" do
    order, refund = create_pending_refund(owner: @owner)
    sign_in_as(@other_user)

    delete withdraw_refund_store_order_path(order, refund_id: refund.id)

    assert_response :not_found
    assert refund.reload.pending?
  end

  test "order owner can withdraw a pending refund through the nested route" do
    order, refund = create_pending_refund(owner: @owner)
    sign_in_as(@owner)

    delete withdraw_refund_store_order_path(order, refund_id: refund.id)

    assert_redirected_to store_order_path(order)
    assert refund.reload.withdrawn?
  end

  private

  def create_pending_refund(owner:)
    order = Commerce::Order.create!(
      public_id: "ord_route_#{SecureRandom.hex(6)}",
      order_number: "RTE#{SecureRandom.hex(4).upcase}",
      user: owner,
      status: "paid",
      subtotal_cents: 1_000,
      total_cents: 1_000,
      currency: "CNY"
    )
    payment = Payments::Record.create!(
      order: order,
      provider: "fake",
      status: "succeeded",
      amount_cents: 1_000,
      currency: "CNY",
      provider_payment_id: "route_#{SecureRandom.hex(6)}"
    )
    refund = Commerce::Refund.create!(
      order: order,
      payment_record: payment,
      requested_by: owner,
      requested_by_customer: true,
      status: :pending,
      amount_cents: 500
    )
    [ order, refund ]
  end

  def create_product(suffix)
    Commerce::Product.create!(
      public_id: "prod_route_#{suffix}_#{SecureRandom.hex(5)}",
      name: "Route #{suffix}",
      slug: "route-#{suffix}-#{SecureRandom.hex(5)}",
      product_type: "digital",
      status: "active",
      price_cents: 1_000,
      currency: "CNY"
    )
  end
end
