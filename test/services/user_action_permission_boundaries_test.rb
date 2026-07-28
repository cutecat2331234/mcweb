# frozen_string_literal: true

require "test_helper"

class UserActionPermissionBoundariesTest < ActiveSupport::TestCase
  setup do
    @actor = create_user(account_type: "staff")
    @target = create_user
    grant_permission(@actor, "admin.access")
  end

  test "admin access does not authorize forum moderation services" do
    assert Community::CreateUserWarning.call(
      actor: @actor,
      user: @target,
      reason: "warning",
      points: 1
    ).failure?
    assert Community::CreateStaffNote.call(
      actor: @actor,
      user: @target,
      body: "private note"
    ).failure?
    assert Community::SpamCleaner.call(actor: @actor, user: @target).failure?
    assert Community::CreateUserSilence.call(actor: @actor, user: @target).failure?
    assert Community::RemoveUserSilence.call(actor: @actor, user: @target).failure?
  end

  test "admin access and order read do not authorize store credit adjustments" do
    grant_permission(@actor, "store.orders.read")

    result = Commerce::AdjustStoreCredit.call(
      actor: @actor,
      user: @target,
      amount_cents: 500,
      note: "credit"
    )

    assert_predicate result, :failure?
    assert_equal 0, @target.reload.store_credit_cents
  end

  test "dedicated store credit permission authorizes the service" do
    grant_permission(@actor, "store.credit.adjust")
    authorization = issue_store_credit_adjustment(
      actor: @actor,
      user: @target,
      amount_cents: 500,
      note: "credit"
    )

    result = Commerce::AdjustStoreCredit.call(
      actor: @actor,
      user: @target,
      amount_cents: 500,
      request_id: authorization[:request_id],
      authorization_token: authorization[:token],
      confirmation: authorization[:confirmation],
      note: "credit"
    )

    assert_predicate result, :success?
    assert_equal 500, @target.reload.store_credit_cents
  end

  test "admin access does not authorize forum and store staff write services" do
    topic = create_topic(user: @actor)
    order = create_order(user: @target)
    review = create_review(user: @target)

    assert_no_difference -> { Community::TopicStaffNote.where(topic: topic).count } do
      result = Community::CreateTopicStaffNote.call(
        actor: @actor,
        topic: topic,
        body: "private note"
      )
      assert_predicate result, :failure?
    end

    assert_no_difference -> { Commerce::OrderStaffNote.where(order: order).count } do
      result = Commerce::CreateOrderStaffNote.call(
        actor: @actor,
        order: order,
        body: "private note"
      )
      assert_predicate result, :failure?
    end

    assert_no_changes -> { review.reload.merchant_reply } do
      result = Commerce::ReplyToReview.call(
        actor: @actor,
        review: review,
        body: "merchant reply"
      )
      assert_predicate result, :failure?
    end
  end

  test "admin access does not grant community staff policy exemptions" do
    @actor.update!(forum_trust_level_override: 0)
    @target.update!(forum_pm_policy: "staff_only")
    SiteSetting.set("forum.require_post_approval_below_tl", "1")
    SiteSetting.set("forum.min_trust_level_profile_post", "1")

    assert_not Community::PmPolicy.accepts?(recipient: @target, sender: @actor)
    Mcweb::DeveloperMode.stub(:allow?, false) do
      assert Community::RequiresPostApproval.required_for?(user: @actor)
      assert_not Community::ProfileWallPolicy.can_post?(author: @actor, profile_user: @target)
    end
  end

  test "admin access cannot expose staff-only fields or use staff-only tags" do
    definition = Community::UserFieldDefinition.create!(
      key: "staff_secret_#{SecureRandom.hex(4)}",
      label: "Staff secret",
      field_type: "text",
      visibility: "staff",
      show_on_profile: true
    )
    Community::UserFieldValue.create!(user: @target, definition: definition, value: "secret")

    fields = Community::SerializeUserFields.for(user: @target, viewer: @actor)
    assert_empty fields

    topic = create_topic(user: @actor)
    tag = Community::Tag.create!(
      name: "Staff tag #{SecureRandom.hex(4)}",
      slug: "staff-tag-#{SecureRandom.hex(4)}",
      staff_only: true
    )
    result = Community::SyncTopicTags.call(topic: topic, tag_names: [ tag.name ], user: @actor)

    assert_predicate result, :failure?
    assert_not_includes topic.reload.tags, tag
  end

  test "admin access alone is not selected for product question notifications" do
    product = create_product
    question = Commerce::ProductQuestion.create!(
      product: product,
      user: @target,
      body: "Does this work?"
    )

    result = Commerce::NotifyNewProductQuestion.call(question: question)

    assert_predicate result, :success?
    assert_not Notification.exists?(
      user: @actor,
      notification_type: "commerce.new_product_question"
    )
  end

  private

  def create_topic(user:)
    suffix = SecureRandom.hex(4)
    category = Community::Category.create!(name: "Boundary #{suffix}", slug: "boundary-#{suffix}")
    section = Community::Section.create!(
      category: category,
      name: "Boundary",
      slug: "boundary-section-#{suffix}",
      position: 0
    )
    Community::Topic.create!(
      public_id: "topic_#{SecureRandom.hex(10)}",
      section: section,
      user: user,
      title: "Boundary topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: user,
      replies_count: 0
    )
  end

  def create_order(user:)
    Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.hex(10)}",
      order_number: "BOUNDARY-#{SecureRandom.hex(5)}",
      user: user,
      status: "paid",
      subtotal_cents: 1_000,
      total_cents: 1_000,
      currency: "CNY"
    )
  end

  def create_review(user:)
    product = create_product
    Commerce::Review.create!(
      user: user,
      product: product,
      rating: 5,
      body: "Great",
      status: "published"
    )
  end

  def create_product
    suffix = SecureRandom.hex(4)
    Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.hex(10)}",
      name: "Boundary product",
      slug: "boundary-product-#{suffix}",
      product_type: "virtual",
      status: "active",
      price_cents: 1_000,
      currency: "CNY"
    )
  end
end
