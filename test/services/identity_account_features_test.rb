# frozen_string_literal: true

require "test_helper"

class IdentityAccountFeaturesTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = create_user(email_verified: false)
    @user.update!(
      email_verified: false,
      email_verification_token_digest: Digest::SHA256.hexdigest("verify-token"),
      email_verification_sent_at: 1.hour.ago
    )
  end

  test "resend email verification sends mail for unverified user" do
    assert_enqueued_emails 1 do
      result = Identity::ResendEmailVerification.call(email: @user.email, ip_address: "127.0.0.1")
      assert result.success?
    end
  end

  test "resend email verification is noop for verified user" do
    @user.update!(email_verified: true)

    assert_no_enqueued_emails do
      result = Identity::ResendEmailVerification.call(email: @user.email, ip_address: "127.0.0.1")
      assert result.success?
    end
  end

  test "totp setup stores secret before enable" do
    user = create_user
    user.setup_totp!

    assert_not user.totp_enabled?
    assert user.totp_secret.present?
    assert_equal 10, user.recovery_codes.size
  end

  test "authenticate accepts recovery code when totp enabled" do
    user = create_user
    user.setup_totp!
    user.update!(totp_enabled: true)
    code = user.recovery_codes.first

    result = Identity::AuthenticateUser.call(
      email: user.email,
      password: "password123",
      totp_code: code
    )

    assert result.success?
    assert_equal 9, user.reload.recovery_codes.size
  end
end

class AdminWebsitePagesTest < ActiveSupport::TestCase
  test "website page validates slug format" do
    page = Website::Page.new(title: "Test", slug: "Bad Slug", page_type: "custom", status: "draft")
    assert_not page.valid?
    assert page.errors[:slug].present?
  end

  test "website page can be created with valid attributes" do
    slug = "about-us-#{SecureRandom.hex(4)}"
    page = Website::Page.create!(
      title: "About",
      slug: slug,
      page_type: "custom",
      status: "draft"
    )

    assert page.persisted?
  end
end

class AdminWebsitePagesIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "website.pages.edit")
  end

  test "admin creates website page" do
    sign_in_as(@admin)
    slug = "about-#{SecureRandom.hex(4)}"

    assert_difference -> { Website::Page.count }, 1 do
      post admin_website_pages_path, params: {
        page: { title: "About", slug: slug, page_type: "custom", status: "draft" }
      }
    end

    page = Website::Page.find_by!(slug: slug)
    assert_redirected_to admin_website_page_path(page)
  end
end

class MinecraftNodeUrgentTaskTest < ActiveSupport::TestCase
  setup do
    @node = Minecraft::Node.create!(name: "Urgent Node", status: :offline)
    @server = Minecraft::Server.create!(
      name: "Survival",
      node: @node,
      process_driver: "script",
      working_directory: "/opt/mc"
    )
  end

  test "stop_instance enqueues urgent task and wakes node" do
    result = Minecraft::EnqueueNodeTask.call(
      node: @node,
      server: @server,
      task_type: "stop_instance"
    )

    assert result.success?
    task = result.value[:task]
    assert_equal "urgent", task.priority
    assert @node.reload.tasks_wake_at.present?
  end

  test "claimable scope returns urgent tasks first" do
    normal = Minecraft::NodeTask.create!(
      node: @node,
      task_type: "collect_metrics",
      delivery_id: SecureRandom.uuid,
      status: "pending",
      priority: "normal",
      payload: {}
    )
    urgent = Minecraft::NodeTask.create!(
      node: @node,
      server: @server,
      task_type: "stop_instance",
      delivery_id: SecureRandom.uuid,
      status: "pending",
      priority: "urgent",
      payload: {}
    )

    claimed = @node.node_tasks.claimable.limit(2).pluck(:id)
    assert_equal [ urgent.id, normal.id ], claimed
  end
end

class MinecraftNodeMetricMetadataTest < ActiveSupport::TestCase
  setup do
    @node = Minecraft::Node.create!(name: "meta-node", public_id: "node-meta-#{SecureRandom.hex(4)}")
  end

  test "record node metric snapshot stores metadata" do
    result = Minecraft::RecordNodeMetricSnapshot.call(
      node: @node,
      host_metrics: { "cpu_percent" => 10.0 },
      metadata: { "source" => "test" }
    )

    assert result.success?
    assert_equal({ "source" => "test" }, result.value[:snapshot].metadata)
  end
end
