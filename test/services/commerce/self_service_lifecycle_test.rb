# frozen_string_literal: true

require "test_helper"

class Commerce::RefundSelfServiceLifecycleTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @other_user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_withdraw_#{SecureRandom.hex(6)}",
      order_number: "RWD#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1_000,
      total_cents: 1_000,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      status: "succeeded",
      amount_cents: 1_000,
      currency: "CNY",
      provider_payment_id: "withdraw_#{SecureRandom.hex(8)}"
    )
    @refund = Commerce::Refund.create!(
      order: @order,
      payment_record: @payment,
      requested_by: @user,
      requested_by_customer: true,
      status: :pending,
      amount_cents: 600
    )
  end

  test "owner withdrawal is atomic audited and idempotent and releases the reservation" do
    assert_equal 600, @payment.refunds.reserved.sum(:amount_cents)

    first = Commerce::WithdrawRefund.call(order: @order, refund: @refund, user: @user)
    replay = Commerce::WithdrawRefund.call(order: @order, refund: @refund.reload, user: @user)

    assert first.success?, first.error
    assert replay.success?, replay.error
    assert replay.value[:idempotent]
    assert @refund.reload.withdrawn?
    assert_equal @user.id, @refund.withdrawn_by_id
    assert @refund.withdrawn_at.present?
    assert_equal 0, @payment.refunds.reserved.sum(:amount_cents)
    assert_equal 1, @order.events.where(event_type: "refund_withdrawn").count
    assert_equal 1, AuditLog.where(action: "commerce.refund_withdrawn", resource_id: @refund.id).count
  end

  test "another user and an approved refund cannot be withdrawn" do
    unauthorized = Commerce::WithdrawRefund.call(order: @order, refund: @refund, user: @other_user)
    assert unauthorized.failure?
    assert_equal "refund_withdrawal_unauthorized", unauthorized.code
    assert @refund.reload.pending?

    @refund.update!(status: :approved, approved_by: @other_user, processing_started_at: Time.current)
    late = Commerce::WithdrawRefund.call(order: @order, refund: @refund, user: @user)
    assert late.failure?
    assert_equal "refund_withdrawal_no_longer_available", late.code
    assert_equal I18n.t("mcweb.services.errors.refund_withdrawal_no_longer_available"), late.error
    assert @refund.reload.approved?
  end

  test "pending approved and completed reserve balance while withdrawn does not" do
    @refund.update!(status: :withdrawn, withdrawn_at: Time.current, withdrawn_by: @user)
    %w[pending approved completed].each_with_index do |status, index|
      Commerce::Refund.create!(
        order: @order,
        payment_record: @payment,
        status: status,
        amount_cents: 100,
        requested_by: @user,
        provider_refund_id: status == "completed" ? "completed_#{index}" : nil
      )
    end

    assert_equal 300, @payment.refunds.reserved.sum(:amount_cents)
  end

  test "request refund failures are translated for Chinese users" do
    enable_refund_window!
    anchor_order_payment_at!(@order)

    pending = I18n.with_locale(:"zh-CN") do
      Commerce::RequestRefund.call(order: @order, user: @user, amount_cents: 100)
    end
    assert_equal "refund_already_pending", pending.code
    assert_equal "已有一笔退款申请正在审核中。", pending.error

    @refund.update!(status: :withdrawn, withdrawn_at: Time.current, withdrawn_by: @user)
    completed = Commerce::Refund.create!(
      order: @order,
      payment_record: @payment,
      requested_by: @user,
      requested_by_customer: true,
      status: :completed,
      amount_cents: @payment.amount_cents
    )
    no_balance = I18n.with_locale(:"zh-CN") do
      Commerce::RequestRefund.call(order: @order, user: @user, amount_cents: 100)
    end
    assert_equal "refund_no_balance", no_balance.code
    assert_equal "已没有可退款余额。", no_balance.error

    completed.destroy!
    @refund.destroy!
    @payment.destroy!
    missing = I18n.with_locale(:"zh-CN") do
      Commerce::RequestRefund.call(order: @order, user: @user, amount_cents: 100)
    end
    assert_equal "refund_payment_not_found", missing.code
    assert_equal "该订单没有成功的支付记录。", missing.error
  end

  test "the default customer refund reason stores a stable kind and follows the viewing locale" do
    @refund.destroy!
    enable_refund_window!
    anchor_order_payment_at!(@order)

    result = I18n.with_locale(:"zh-CN") do
      Commerce::RequestRefund.call(order: @order, user: @user, amount_cents: 100)
    end

    assert result.success?, result.error
    refund = result.value.reload
    assert_nil refund.reason
    assert_equal "customer_request", refund.reason_kind
    assert_equal "Customer request", I18n.with_locale(:en) { Commerce::RefundReasonPresenter.label(refund) }
    assert_equal "客户申请", I18n.with_locale(:"zh-CN") { Commerce::RefundReasonPresenter.label(refund) }
  end

  test "a customer supplied refund reason remains verbatim in every locale" do
    @refund.destroy!
    enable_refund_window!
    anchor_order_payment_at!(@order)

    result = Commerce::RequestRefund.call(
      order: @order,
      user: @user,
      amount_cents: 100,
      reason: "The package was damaged"
    )

    assert result.success?, result.error
    refund = result.value.reload
    assert_equal "customer_request", refund.reason_kind
    assert_equal "The package was damaged", refund.reason
    assert_equal refund.reason, I18n.with_locale(:en) { Commerce::RefundReasonPresenter.label(refund) }
    assert_equal refund.reason, I18n.with_locale(:"zh-CN") { Commerce::RefundReasonPresenter.label(refund) }
  end

  test "provider failures without a definitive code are quarantined with a stable refund code" do
    provider = Object.new
    provider.define_singleton_method(:process_refund) do |_refund|
      ServiceResult.failure(error: :stripe_is_not_enabled_or_fully_configured)
    end

    result = Payments::Provider.stub(:for, provider) do
      Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: @refund.amount_cents,
        existing_refund: @refund,
        approved_by: @other_user
      )
    end

    assert result.failure?
    assert_equal "refund_provider_outcome_unknown", result.code
    assert @refund.reload.provider_unknown?
    assert_equal "refund_provider_outcome_unknown", @refund.provider_error_code
    assert_equal @refund.amount_cents, @payment.refunds.reserved.sum(:amount_cents)
  end

  test "approving a customer refund without a replacement reason preserves the customer reason" do
    @refund.update!(reason: "The delivered item was damaged", reason_kind: "customer_request")
    provider = Object.new
    provider.define_singleton_method(:process_refund) do |refund|
      ServiceResult.success(
        provider_refund_id: "preserved_reason_#{refund.id}",
        provider_status: "succeeded"
      )
    end

    result = Payments::Provider.stub(:for, provider) do
      Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: @refund.amount_cents,
        existing_refund: @refund,
        approved_by: @other_user
      )
    end

    assert result.success?, result.error
    assert_equal "The delivered item was damaged", @refund.reload.reason
    assert_equal "customer_request", @refund.reason_kind
    assert_equal @refund.reason, Commerce::RefundReasonPresenter.label(@refund)
  end

  test "a new admin refund preserves its classification and free reason" do
    @refund.destroy!
    provider = Object.new
    provider.define_singleton_method(:process_refund) do |refund|
      ServiceResult.success(
        provider_refund_id: "admin_reason_#{refund.id}",
        provider_status: "succeeded"
      )
    end

    result = Payments::Provider.stub(:for, provider) do
      Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: @payment.amount_cents,
        reason: "Verified support exception",
        reason_kind: "admin_refund",
        approved_by: @other_user
      )
    end

    assert result.success?, result.error
    refund = result.value.reload
    assert_equal "admin_refund", refund.reason_kind
    assert_equal "Verified support exception", refund.reason
    assert_equal refund.reason, Commerce::RefundReasonPresenter.label(refund)
  end
end

class Commerce::ReviewSelfServiceLifecycleTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @other_user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_review_flow_#{SecureRandom.hex(5)}",
      name: "Review flow",
      slug: "review-flow-#{SecureRandom.hex(5)}",
      product_type: "digital",
      status: "active",
      price_cents: 1_000,
      currency: "CNY"
    )
    order = Commerce::Order.create!(
      public_id: "ord_review_flow_#{SecureRandom.hex(5)}",
      order_number: "RVW#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1_000,
      total_cents: 1_000,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: order,
      product: @product,
      product_name: @product.name,
      quantity: 1,
      unit_price_cents: 1_000,
      total_cents: 1_000
    )
    @review = Commerce::CreateReview.call(
      user: @user,
      product: @product,
      rating: 5,
      body: "Original"
    ).value
  end

  test "create and update are separate and only the author may update" do
    created_audit = AuditLog.find_by!(action: "commerce.review_created", resource_id: @review.id)
    refute_includes created_audit.after_state.to_json, "Original"
    assert created_audit.after_state["body_sha256"].present?

    duplicate = Commerce::CreateReview.call(user: @user, product: @product, rating: 1, body: "Duplicate")
    assert duplicate.failure?

    unauthorized = Commerce::UpdateReview.call(
      user: @other_user,
      review: @review,
      rating: 1,
      body: "Changed",
      expected_version: @review.lock_version
    )
    assert unauthorized.failure?
    assert_equal "Original", @review.reload.body

    updated = Commerce::UpdateReview.call(
      user: @user,
      review: @review,
      rating: 4,
      body: "Updated",
      expected_version: @review.lock_version
    )
    assert updated.success?, updated.error
    assert_equal [ 4, "Updated" ], @review.reload.values_at(:rating, :body)
    audit = AuditLog.find_by!(action: "commerce.review_updated", resource_id: @review.id)
    refute_includes audit.before_state.to_json, "Original"
    refute_includes audit.after_state.to_json, "Updated"
    assert audit.after_state["body_sha256"].present?
  end

  test "author deletion can be deliberately republished but staff hidden content cannot" do
    deleted = Commerce::DeleteReview.call(user: @user, review: @review)
    assert deleted.success?, deleted.error
    assert @review.reload.deleted?
    assert_equal 0, @product.reviews.published.count

    republished = Commerce::CreateReview.call(user: @user, product: @product, rating: 3, body: "Returned")
    assert republished.success?, republished.error
    assert @review.reload.published?
    assert_nil @review.deleted_at

    @review.update!(status: :hidden)
    blocked = Commerce::CreateReview.call(user: @user, product: @product, rating: 5, body: "Bypass")
    assert blocked.failure?
    assert @review.reload.hidden?
  end

  test "staff moderation is locked idempotent and cannot restore an author tombstone" do
    hidden = Commerce::ModerateReview.call(review: @review, actor: @other_user, target_status: :hidden)
    replay = Commerce::ModerateReview.call(review: @review, actor: @other_user, target_status: :hidden)
    restored = Commerce::ModerateReview.call(review: @review, actor: @other_user, target_status: :published)

    assert hidden.success?, hidden.error
    assert replay.success?, replay.error
    assert replay.value[:idempotent]
    assert restored.success?, restored.error
    assert @review.reload.published?
    assert_equal 2, AuditLog.where(action: "commerce.review_moderation_status_changed", resource_id: @review.id).count

    Commerce::DeleteReview.call(user: @user, review: @review)
    blocked = Commerce::ModerateReview.call(review: @review, actor: @other_user, target_status: :published)
    assert blocked.failure?
    assert_equal "review_not_moderatable", blocked.code
    assert @review.reload.deleted?
  end

  test "explicit photo retention rejects foreign attachment identifiers" do
    @review.photos.attach(io: StringIO.new("image"), filename: "review.jpg", content_type: "image/jpeg")
    attachment_id = @review.photos.attachments.first.id

    invalid = Commerce::UpdateReview.call(
      user: @user,
      review: @review,
      rating: 5,
      body: "Still here",
      retained_photo_ids: [ attachment_id + 10_000 ],
      photo_selection_present: true,
      expected_version: @review.reload.lock_version
    )
    assert invalid.failure?
    assert @review.reload.photos.attached?

    removed = nil
    assert_enqueued_jobs 1, only: ActiveStorage::PurgeJob do
      removed = Commerce::UpdateReview.call(
        user: @user,
        review: @review,
        rating: 5,
        body: "No photo",
        retained_photo_ids: [],
        photo_selection_present: true,
        expected_version: @review.reload.lock_version
      )
    end
    assert removed.success?, removed.error
    assert_not @review.reload.photos.attached?
  end

  test "a rolled back photo update does not enqueue deletion or detach the original" do
    @review.photos.attach(io: StringIO.new("image"), filename: "rollback.jpg", content_type: "image/jpeg")
    clear_enqueued_jobs
    original = Administration::AuditLogger.method(:call)
    Administration::AuditLogger.define_singleton_method(:call) { |**| raise "audit unavailable" }

    assert_no_enqueued_jobs only: ActiveStorage::PurgeJob do
      assert_raises(RuntimeError) do
        Commerce::UpdateReview.call(
          user: @user,
          review: @review,
          rating: 4,
          body: "Would roll back",
          retained_photo_ids: [],
          photo_selection_present: true,
          expected_version: @review.reload.lock_version
        )
      end
    end
    assert @review.reload.photos.attached?
  ensure
    Administration::AuditLogger.define_singleton_method(:call, original) if original
  end

  test "a stale or revisionless review edit cannot overwrite a newer tab" do
    shared_version = @review.lock_version
    missing = Commerce::UpdateReview.call(
      user: @user,
      review: @review,
      rating: 4,
      body: "Missing revision"
    )
    assert missing.failure?
    assert_equal "review_revision_required", missing.code

    first = Commerce::UpdateReview.call(
      user: @user,
      review: @review,
      rating: 4,
      body: "First tab",
      expected_version: shared_version
    )
    second = Commerce::UpdateReview.call(
      user: @user,
      review: @review,
      rating: 2,
      body: "Stale second tab",
      expected_version: shared_version
    )

    assert first.success?, first.error
    assert second.failure?
    assert_equal "review_update_conflict", second.code
    assert_equal [ 4, "First tab" ], @review.reload.values_at(:rating, :body)
  end
end

class Commerce::ProductContentSelfServiceLifecycleTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @other_user = create_user
    @staff = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_qa_flow_#{SecureRandom.hex(5)}",
      name: "Q&A flow",
      slug: "qa-flow-#{SecureRandom.hex(5)}",
      product_type: "digital",
      status: "active",
      price_cents: 1_000,
      currency: "CNY"
    )
    @question = Commerce::CreateProductQuestion.call(
      user: @author,
      product: @product,
      body: "Original question"
    ).value
    @answer = Commerce::AnswerProductQuestion.call(
      user: @other_user,
      question: @question,
      body: "Original answer"
    ).value
  end

  test "question author can edit and soft delete without cascading answers" do
    denied = Commerce::UpdateProductQuestion.call(
      user: @other_user,
      question: @question,
      body: "Hijacked",
      expected_version: @question.lock_version
    )
    assert denied.failure?

    updated = Commerce::UpdateProductQuestion.call(
      user: @author,
      question: @question,
      body: "Edited question",
      expected_version: @question.lock_version
    )
    assert updated.success?, updated.error
    assert @question.reload.edited_at.present?
    audit = AuditLog.find_by!(action: "commerce.product_question_updated", resource_id: @question.id)
    refute_includes audit.before_state.to_json, "Original question"
    refute_includes audit.after_state.to_json, "Edited question"
    assert_equal [ "body" ], audit.metadata["changed_fields"]

    deleted = Commerce::DeleteProductQuestion.call(user: @author, question: @question)
    assert deleted.success?, deleted.error
    assert @question.reload.deleted?
    assert Commerce::ProductAnswer.exists?(@answer.id)
    assert_equal 0, @product.questions.visible.count
  end

  test "answer edit delete and helpful counts respect visibility" do
    updated = Commerce::UpdateProductAnswer.call(
      user: @other_user,
      answer: @answer,
      body: "Edited answer",
      expected_version: @answer.lock_version
    )
    assert updated.success?, updated.error
    assert @answer.reload.edited_at.present?
    audit = AuditLog.find_by!(action: "commerce.product_answer_updated", resource_id: @answer.id)
    refute_includes audit.before_state.to_json, "Original answer"
    refute_includes audit.after_state.to_json, "Edited answer"

    Commerce::AnswerHelpfulVote.create!(user: @author, answer: @answer)
    hidden = Commerce::HideProductAnswer.call(answer: @answer, actor: @staff)
    assert hidden.success?, hidden.error
    assert_equal 0, @question.answers.visible.count
    vote = Commerce::ToggleAnswerHelpful.call(user: @staff, answer: @answer)
    assert vote.failure?

    restored = Commerce::ShowProductAnswer.call(answer: @answer, actor: @staff)
    assert restored.success?, restored.error
    deleted = Commerce::DeleteProductAnswer.call(user: @other_user, answer: @answer)
    assert deleted.success?, deleted.error
    assert @answer.reload.deleted?
    assert_equal 0, @question.answers.visible.count
  end

  test "restoring a parent does not restore an independently hidden answer" do
    Commerce::HideProductAnswer.call(answer: @answer, actor: @staff)
    Commerce::HideProductQuestion.call(question: @question, actor: @staff)
    Commerce::ShowProductQuestion.call(question: @question, actor: @staff)

    assert @question.reload.published?
    assert @answer.reload.hidden?
  end

  test "official answer edit requires the permission to still be held" do
    @answer.update!(official: true)
    denied = Commerce::UpdateProductAnswer.call(
      user: @other_user,
      answer: @answer,
      body: "Official edit",
      expected_version: @answer.lock_version
    )
    assert denied.failure?

    grant_permission(@other_user, "store.questions.answer")
    allowed = Commerce::UpdateProductAnswer.call(
      user: @other_user.reload,
      answer: @answer,
      body: "Official edit",
      expected_version: @answer.reload.lock_version
    )
    assert allowed.success?, allowed.error

    revoked_user = create_user
    @answer.reload.update!(user: revoked_user)
    delete_denied = Commerce::DeleteProductAnswer.call(user: revoked_user, answer: @answer)
    assert delete_denied.failure?
    grant_permission(revoked_user, "store.questions.answer")
    delete_allowed = Commerce::DeleteProductAnswer.call(user: revoked_user.reload, answer: @answer)
    assert delete_allowed.success?, delete_allowed.error
  end


  test "stale question and answer edits cannot overwrite a newer tab" do
    question_version = @question.lock_version
    question_missing = Commerce::UpdateProductQuestion.call(
      user: @author,
      question: @question,
      body: "Missing revision"
    )
    assert_equal "question_revision_required", question_missing.code
    question_first = Commerce::UpdateProductQuestion.call(
      user: @author,
      question: @question,
      body: "Question first tab",
      expected_version: question_version
    )
    question_stale = Commerce::UpdateProductQuestion.call(
      user: @author,
      question: @question,
      body: "Question stale tab",
      expected_version: question_version
    )
    assert question_first.success?, question_first.error
    assert_equal "question_update_conflict", question_stale.code
    assert_equal "Question first tab", @question.reload.body

    answer_version = @answer.lock_version
    answer_missing = Commerce::UpdateProductAnswer.call(
      user: @other_user,
      answer: @answer,
      body: "Missing revision"
    )
    assert_equal "answer_revision_required", answer_missing.code
    answer_first = Commerce::UpdateProductAnswer.call(
      user: @other_user,
      answer: @answer,
      body: "Answer first tab",
      expected_version: answer_version
    )
    answer_stale = Commerce::UpdateProductAnswer.call(
      user: @other_user,
      answer: @answer,
      body: "Answer stale tab",
      expected_version: answer_version
    )
    assert answer_first.success?, answer_first.error
    assert_equal "answer_update_conflict", answer_stale.code
    assert_equal "Answer first tab", @answer.reload.body
  end

  test "official answer update and deletion recheck a fresh actor after permission revocation" do
    @answer.update!(official: true)
    grant_permission(@other_user, "store.questions.answer")
    stale_actor = @other_user.reload
    assert stale_actor.permission?("store.questions.answer")
    permission = Permission.find_by!(key: "store.questions.answer")
    role = stale_actor.roles.joins(:permissions).find_by!(permissions: { id: permission.id })
    role.revoke_permission!(permission)

    update_result = Commerce::UpdateProductAnswer.call(
      user: stale_actor,
      answer: @answer,
      body: "Must not be accepted",
      expected_version: @answer.reload.lock_version
    )
    assert update_result.failure?
    assert_equal "official_answer_permission_required", update_result.code
    assert_equal "Original answer", @answer.reload.body

    role.grant_permission!(permission)
    stale_actor = stale_actor.reload
    assert stale_actor.permission?("store.questions.answer")
    role.revoke_permission!(permission)

    delete_result = Commerce::DeleteProductAnswer.call(user: stale_actor, answer: @answer)
    assert delete_result.failure?
    assert_equal "official_answer_permission_required", delete_result.code
    assert @answer.reload.published?
  end

  test "answer creation rechecks a fresh actor after official permission revocation" do
    staff = create_user
    grant_permission(staff, "store.questions.answer")
    stale_actor = staff.reload
    assert stale_actor.permission?("store.questions.answer")
    permission = Permission.find_by!(key: "store.questions.answer")
    role = stale_actor.roles.joins(:permissions).find_by!(permissions: { id: permission.id })
    role.revoke_permission!(permission)

    result = Commerce::AnswerProductQuestion.call(
      user: stale_actor,
      question: @question,
      body: "Created after revocation"
    )

    assert result.success?, result.error
    refute result.value.reload.official?
  end
end
