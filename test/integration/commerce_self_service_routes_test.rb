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
      params: { question: { body: "Edited question", expected_version: @question.lock_version } }
    assert_redirected_to store_product_path(@product)

    patch store_product_update_answer_path(
      @product,
      question_id: @question.id,
      answer_id: @answer.id
    ), params: { answer: { body: "Edited answer", expected_version: @answer.lock_version } }
    assert_redirected_to store_product_path(@product)

    patch store_product_review_path(@product, review),
      params: {
        review: {
          rating: 4,
          body: "Edited review",
          expected_version: review.lock_version,
          photo_selection_present: true
        }
      }
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
    assert_equal @question.lock_version, question.fetch(:lock_version)
    assert_equal store_product_update_answer_path(
      @product,
      question_id: @question.id,
      answer_id: @answer.id
    ), answer.fetch(:update_url)
    assert_equal @answer.lock_version, answer.fetch(:lock_version)
    assert_equal store_product_review_path(@product, review),
      inertia.props.deep_symbolize_keys.fetch(:updateReviewUrl)
    assert_equal review.lock_version, inertia.props.deep_symbolize_keys.fetch(:userReview).fetch(:lock_version)
  end

  test "explicit photo selection removes the final review photo when multipart omits an empty array" do
    review = Commerce::Review.create!(
      user: @owner,
      product: @product,
      rating: 5,
      body: "Photo review",
      status: :published
    )
    review.photos.attach(
      io: StringIO.new("last photo"),
      filename: "last.jpg",
      content_type: "image/jpeg"
    )
    sign_in_as(@owner)

    patch store_product_review_path(@product, review),
      params: {
        review: {
          rating: 5,
          body: "Photo removed",
          expected_version: review.reload.lock_version,
          photo_selection_present: "1"
        }
      }

    assert_redirected_to store_product_path(@product)
    assert_nil flash[:alert], flash[:alert]
    assert_not review.reload.photos.attached?
  end

  test "owners can update and delete their content after a product is archived" do
    review = Commerce::Review.create!(
      user: @owner,
      product: @product,
      rating: 5,
      body: "Archived review",
      status: :published
    )
    @product.update!(status: :archived)
    sign_in_as(@owner)

    patch store_product_review_path(@product, review), params: {
      review: {
        rating: 4,
        body: "Edited while archived",
        expected_version: review.lock_version,
        photo_selection_present: true
      }
    }
    assert_redirected_to store_products_path
    assert_equal "Edited while archived", review.reload.body

    patch store_product_update_question_path(@product, question_id: @question.id), params: {
      question: { body: "Archived question edit", expected_version: @question.lock_version }
    }
    assert_redirected_to store_products_path
    assert_equal "Archived question edit", @question.reload.body

    patch store_product_update_answer_path(
      @product,
      question_id: @question.id,
      answer_id: @answer.id
    ), params: { answer: { body: "Archived answer edit", expected_version: @answer.lock_version } }
    assert_redirected_to store_products_path
    assert_equal "Archived answer edit", @answer.reload.body

    delete store_product_delete_answer_path(@product, question_id: @question.id, answer_id: @answer.id)
    assert_redirected_to store_products_path
    assert @answer.reload.deleted?

    delete store_product_delete_question_path(@product, question_id: @question.id)
    assert_redirected_to store_products_path
    assert @question.reload.deleted?

    delete store_product_review_path(@product, review)
    assert_redirected_to store_products_path
    assert review.reload.deleted?
  end

  test "customer success flashes resolve in Chinese" do
    review = Commerce::Review.create!(
      user: @owner,
      product: @product,
      rating: 5,
      body: "Localized review",
      status: :published
    )
    sign_in_as(@owner)

    patch store_product_review_path(@product, review), params: {
      review: {
        rating: 4,
        body: "Localized review update",
        expected_version: review.lock_version,
        photo_selection_present: true
      }
    }
    assert_equal I18n.with_locale(:"zh-CN") { I18n.t("mcweb.flash.review_updated") }, flash[:notice]

    delete store_product_review_path(@product, review)
    assert_equal I18n.with_locale(:"zh-CN") { I18n.t("mcweb.flash.review_deleted") }, flash[:notice]

    delete store_product_delete_question_path(@product, question_id: @question.id)
    assert_equal I18n.with_locale(:"zh-CN") { I18n.t("mcweb.flash.question_deleted") }, flash[:notice]
  end

  test "staff question moderation flashes resolve in English" do
    staff = create_user(account_type: "owner", locale: "en")
    sign_in_as(staff)

    patch hide_admin_store_product_question_path(@question)
    assert_redirected_to admin_store_product_questions_path
    assert_nil flash[:alert], flash[:alert]
    assert_equal I18n.with_locale(:en) { I18n.t("mcweb.flash.question_hidden") }, flash[:notice]
    refute_match(/Translation missing/, flash[:notice])

    patch unhide_admin_store_product_question_path(@question)
    assert_redirected_to admin_store_product_questions_path
    assert_nil flash[:alert], flash[:alert]
    assert_equal I18n.with_locale(:en) { I18n.t("mcweb.flash.question_restored") }, flash[:notice]
    refute_match(/Translation missing/, flash[:notice])
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

  test "order serialization translates a stable default refund reason in the active locale" do
    order, refund = create_pending_refund(owner: @owner)
    refund.update!(reason: nil, reason_kind: "customer_request")
    sign_in_as(@owner)

    get store_order_path(order)
    assert_response :success
    localized_refund = inertia.props.deep_symbolize_keys.fetch(:order).fetch(:refunds).find do |entry|
      entry[:id] == refund.id
    end
    assert_equal "客户申请", localized_refund.fetch(:reason)

    @owner.update!(locale: "en")
    get store_order_path(order)
    assert_response :success
    localized_refund = inertia.props.deep_symbolize_keys.fetch(:order).fetch(:refunds).find do |entry|
      entry[:id] == refund.id
    end
    assert_equal "Customer request", localized_refund.fetch(:reason)
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
