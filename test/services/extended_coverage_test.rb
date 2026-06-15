# frozen_string_literal: true

require "test_helper"

class Identity::VerifyEmailTest < ActiveSupport::TestCase
  test "verifies email with valid token" do
    token = SecureRandom.urlsafe_base64(32)
    user = User.create!(
      email: "verify@example.com",
      username: "verifyuser",
      password: "password123",
      password_confirmation: "password123",
      email_verified: false,
      email_verification_token_digest: Digest::SHA256.hexdigest(token),
      email_verification_sent_at: Time.current
    )

    result = Identity::VerifyEmail.call(token: token)
    assert result.success?
    assert user.reload.email_verified?
  end
end

class Identity::ResetPasswordTest < ActiveSupport::TestCase
  test "requests and completes password reset" do
    user = create_user(email: "reset@example.com", username: "resetuser")
    request = Identity::ResetPassword.call(email: "reset@example.com")
    assert request.success?
    token = request.value[:reset_token]

    complete = Identity::ResetPassword.call(token: token, new_password: "newpassword456")
    assert complete.success?
    assert Identity::AuthenticateUser.call(
      email: "reset@example.com",
      password: "newpassword456",
      ip_address: "127.0.0.1",
      user_agent: "Test"
    ).success?
  end
end

class Website::PagePublisherTest < ActiveSupport::TestCase
  test "publishes page and creates revision rollback snapshot" do
    author = create_user
    page = Website::Page.create!(
      public_id: "page_pub1",
      title: "About",
      slug: "about",
      page_type: "custom",
      status: "draft"
    )

    result = Website::PagePublisher.call(page: page, actor: author)
    assert result.success?
    assert_equal "published", page.reload.status

    page.create_revision!(author: author)
    page.update!(title: "Changed Title")
    revision = page.revisions.ordered.first

    page.update!(
      title: revision.snapshot["title"],
      status: revision.snapshot["status"]
    )
    assert_equal "About", page.reload.title
  end
end

class Community::TopicModerationTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @category = Community::Category.find_or_create_by!(slug: "mod-test") { |c| c.name = "Mod" }
    @section = Community::Section.find_or_create_by!(category: @category, slug: "mod-general") do |s|
      s.name = "Mod General"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Moderation topic",
      body: "Opening post for moderation tests.",
      ip_address: "127.0.0.1"
    ).value
  end

  test "locks topic and prevents replies" do
    @topic.lock_topic!
    assert @topic.reload.locked?

    result = Community::CreatePost.call(
      user: @user,
      topic: @topic,
      body: "Should fail",
      ip_address: "127.0.0.1"
    )
    assert result.failure?
  end

  test "moves topic to another section" do
    other = Community::Section.create!(
      category: @category,
      name: "Other",
      slug: "other-section",
      position: 1
    )
    @topic.update!(section: other)
    assert_equal other.id, @topic.reload.forum_section_id
  end
end

class Community::ReportTest < ActiveSupport::TestCase
  test "creates report for moderation queue" do
    user = create_user
    category = Community::Category.find_or_create_by!(slug: "report-cat") { |c| c.name = "Report" }
    section = Community::Section.find_or_create_by!(category: category, slug: "report-sec") do |s|
      s.name = "Report Sec"
      s.position = 0
    end
    topic = Community::CreateTopic.call(
      user: user,
      section: section,
      title: "Report me",
      body: "Please review this topic.",
      ip_address: "127.0.0.1"
    ).value

    report = Community::Report.create!(
      reporter: user,
      reportable: topic,
      reason: "spam",
      status: "pending"
    )
    assert report.persisted?
    assert_includes Community::Report.pending_review, report
  end
end

class Commerce::ConcurrentPaymentTest < ActiveSupport::TestCase
  parallelize(workers: 1)

  test "concurrent payment confirmation is idempotent" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_conc1",
      order_number: "ORD-CONC-001",
      user: user,
      status: "pending",
      subtotal_cents: 2000,
      total_cents: 2000,
      discount_cents: 0,
      currency: "CNY"
    )
    payment = Payments::Record.create!(
      order: order,
      provider: "fake",
      status: "pending",
      amount_cents: 2000,
      currency: "CNY"
    )

    threads = Array.new(5) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Commerce::ConfirmPayment.call(payment_record: payment, provider_payment_id: "conc_pay_1")
        end
      end
    end
    results = threads.map(&:value)
    assert results.all?(&:success?)
    assert_equal 1, Payments::Record.where(order: order, status: "succeeded").count
    assert_equal "paid", order.reload.status
  end
end

class Minecraft::TaskDispatcherTest < ActiveSupport::TestCase
  setup do
    @server = Minecraft::Server.create!(
      public_id: "srv_dispatch1",
      name: "Dispatch Server",
      connector_secret: "secret_#{SecureRandom.hex(16)}"
    )
    @order = Commerce::Order.create!(
      public_id: "ord_disp1",
      order_number: "ORD-DISP-001",
      user: create_user,
      status: "paid",
      subtotal_cents: 100,
      total_cents: 100,
      discount_cents: 0,
      currency: "CNY"
    )
    @order_item = Commerce::OrderItem.create!(
      order: @order,
      product_name: "Item",
      unit_price_cents: 100,
      quantity: 1,
      total_cents: 100,
      fulfillment_snapshot: {}
    )
    @fulfillment = Commerce::Fulfillment.create!(
      order: @order,
      order_item: @order_item,
      status: "pending",
      delivery_id: SecureRandom.uuid
    )
    @task = Minecraft::ConnectorTask.create!(
      server: @server,
      fulfillment: @fulfillment,
      task_type: "fulfillment",
      status: "claimed",
      delivery_id: @fulfillment.delivery_id
    )
  end

  test "completes task and is idempotent on retry" do
    first = Minecraft::TaskDispatcher.call(
      server: @server,
      task: @task,
      result: { ok: true },
      action: :complete
    )
    assert first.success?
    assert_equal "fulfilled", @fulfillment.reload.status

    second = Minecraft::TaskDispatcher.call(
      server: @server,
      task_id: @task.id,
      result: { ok: true },
      action: :complete
    )
    assert second.success?
    assert second.value[:idempotent]
    assert_equal 1, Minecraft::ProcessedDelivery.where(server: @server, delivery_id: @fulfillment.delivery_id).count
  end
end

class Administration::AuditLoggerTest < ActiveSupport::TestCase
  test "records dangerous admin operation metadata" do
    admin = create_user
    result = Administration::AuditLogger.call(
      actor: admin,
      action: "commerce.refund_processed",
      metadata: { amount_cents: 500 },
      ip_address: "10.0.0.1",
      user_agent: "AdminBrowser",
      reason: "Customer request"
    )

    assert result.success?
    log = result.value
    assert_equal "commerce.refund_processed", log.action
    assert_equal "10.0.0.1", log.ip_address
    assert_equal "Customer request", log.reason
  end
end

class Administration::RateLimiterTest < ActiveSupport::TestCase
  test "blocks requests after limit exceeded" do
    key = "test:#{SecureRandom.hex(4)}"
    3.times { Administration::RateLimiter.call(key: key, limit: 3, window: 1.minute) }
    result = Administration::RateLimiter.call(key: key, limit: 3, window: 1.minute)
    assert result.failure?
  end
end

class Operations::HealthCheckerTest < ActiveSupport::TestCase
  test "returns health status" do
    result = Operations::HealthChecker.call
    assert result.success?
    assert_includes %w[ok degraded], result.value[:status]
    assert_equal "ok", result.value[:checks][:database][:status]
  end
end

class Commerce::ProcessRefundTest < ActiveSupport::TestCase
  test "processes refund with audit trail" do
    user = create_user
    admin = create_user
    grant_permission(admin, "store.orders.refund")
    order = Commerce::Order.create!(
      public_id: "ord_ref1",
      order_number: "ORD-REF-001",
      user: user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )
    payment = Payments::Record.create!(
      order: order,
      provider: "fake",
      status: "succeeded",
      amount_cents: 1000,
      currency: "CNY",
      provider_payment_id: "fake_refund_pay"
    )

    result = Commerce::ProcessRefund.call(
      order: order,
      payment_record: payment,
      amount_cents: 1000,
      reason: "Test refund",
      approved_by: admin
    )
    assert result.success?
    assert_equal "completed", result.value.status
    assert AuditLog.exists?(action: "commerce.refund_processed")
  end
end

class Website::BlockSanitizerUrlTest < ActiveSupport::TestCase
  test "strips javascript urls" do
    html = '<a href="javascript:alert(1)">click</a>'
    result = Website::BlockSanitizer.call(html: html)
    assert result.success?
    assert_not_includes result.value.to_s, "javascript:"
  end
end
