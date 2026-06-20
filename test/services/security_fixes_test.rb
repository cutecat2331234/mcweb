# frozen_string_literal: true

require "test_helper"

class SecurityFixesTest < ActiveSupport::TestCase
  setup do
    @staff = create_user
    @target = create_user
    grant_permission(@staff, "store.orders.read")
    @server = Minecraft::Server.create!(
      name: "Test Server",
      public_id: "srv-sec-#{SecureRandom.hex(4)}",
      connector_secret: "test-secret-#{SecureRandom.hex(16)}"
    )
  end

  test "adjust store credit rejects self adjustment" do
    result = Commerce::AdjustStoreCredit.call(
      actor: @staff,
      user: @staff,
      amount_cents: 1000
    )

    assert_not result.success?
    assert_includes result.error, "无权"
  end

  test "adjust store credit allows adjusting another user" do
    result = Commerce::AdjustStoreCredit.call(
      actor: @staff,
      user: @target,
      amount_cents: 500
    )

    assert result.success?
    assert_equal 500, @target.reload.store_credit_cents
  end

  test "adjust store credit rejects reducing below pending reservation" do
    @target.update!(store_credit_cents: 1000)
    Commerce::Order.create!(
      public_id: "ord_sc_res_#{SecureRandom.hex(4)}",
      order_number: "ORD-SC-RES-#{SecureRandom.hex(4)}",
      user: @target,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 200,
      store_credit_amount_cents: 800,
      discount_cents: 0,
      currency: "CNY"
    )

    result = Commerce::AdjustStoreCredit.call(
      actor: @staff,
      user: @target,
      amount_cents: -500
    )

    assert_not result.success?
    assert_equal I18n.t("mcweb.services.errors.store_credit_below_reserved"), result.error
    assert_equal 1000, @target.reload.store_credit_cents
  end

  test "saved search rejects private webhook urls" do
    search = Community::SavedSearch.new(
      user: @target,
      name: "Test",
      query: "foo",
      webhook_url: "http://127.0.0.1/hook",
      filters: {}
    )

    assert_not search.valid?
    assert_includes search.errors[:webhook_url], "不能指向内网或本地地址"
  end

  test "sync profile fields rejects players not on server" do
    player_ref = Minecraft::PlayerRef.resolve(
      uuid: SecureRandom.uuid,
      platform: "java",
      username: "OfflinePlayer"
    )

    result = Minecraft::SyncProfileFields.call(
      server: @server,
      payload: {
        "uuid" => player_ref.active_identity.external_uuid,
        "platform" => "java",
        "username" => "OfflinePlayer",
        "fields" => [ { "key" => "rank", "value" => "vip" } ]
      }
    )

    assert_not result.success?
    assert_includes result.error, "not associated"
  end

  test "sync presence rejects join without online_player_uuids" do
    result = Minecraft::SyncPresence.call(
      server: @server,
      payload: {
        "uuid" => SecureRandom.uuid,
        "platform" => "java",
        "username" => "OfflinePlayer",
        "event" => "player.join"
      }
    )

    assert_not result.success?
    assert_includes result.error, "online_player_uuids"
  end

  test "stripe provider refuses fake fallback in production" do
    Payments::ProviderConfig.where(provider: "stripe").delete_all
    order = Commerce::Order.create!(
      public_id: "ord_sec_#{SecureRandom.hex(4)}",
      order_number: "ORD-SEC-001",
      user: @target,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )
    payment = Payments::Record.create!(
      order: order,
      provider: "stripe",
      status: "pending",
      amount_cents: 1000,
      currency: "CNY"
    )

    production_env = ActiveSupport::EnvironmentInquirer.new("production")
    singleton = class << Rails; self; end
    original_env = Rails.env
    singleton.define_method(:env) { production_env }
    begin
      result = Payments::StripeProvider.new.create_payment(payment)
      assert_not result.success?
      assert_includes result.error, "Stripe"
    ensure
      singleton.define_method(:env) { original_env }
    end
  end

  test "order webhook dispatch skips private urls" do
    SiteSetting.set("store.order_webhook_url", "http://127.0.0.1/hook")
    order = Commerce::Order.create!(
      public_id: "ord_sec2_#{SecureRandom.hex(4)}",
      order_number: "ORD-SEC2-001",
      user: @target,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )

    assert_no_enqueued_jobs only: Commerce::DispatchOrderWebhookJob do
      result = Commerce::DispatchOrderWebhook.call(order: order, event_type: "order.created")
      assert result.success?
      assert result.value[:skipped]
    end
  end

  test "test order webhook rejects private urls" do
    SiteSetting.set("store.order_webhook_url", "http://192.168.0.1/hook")

    result = Commerce::DispatchTestOrderWebhook.call

    assert_not result.success?
    assert_includes result.error, "内网"
  end

  test "sync file path rejects traversal outside allowed roots" do
    assert_nil Minecraft::SyncFilePath.resolve("storage/../../../config/local.yml")
  end

  test "sync file path allows files under storage" do
    path = "storage/sync-path-test-#{SecureRandom.hex(4)}.txt"
    FileUtils.mkdir_p(Rails.root.join("storage"))
    File.write(Rails.root.join(path), "ok")

    resolved = Minecraft::SyncFilePath.resolve(path)
    assert resolved.file?
    assert Minecraft::SyncFilePath.allowed?(resolved)
  end
end

class RssArchivedTopicSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "rss-sec-cat-#{SecureRandom.hex(3)}") { |c| c.name = "RSS Sec" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "rss-sec-sec-#{SecureRandom.hex(3)}") do |s|
      s.name = "RSS Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Archived RSS #{SecureRandom.hex(4)}",
      body: "Secret archived content",
      ip_address: "127.0.0.1"
    ).value
    @topic.update!(archived_at: Time.current)
  end

  test "topic rss hides archived topics from anonymous users" do
    get forum_topic_rss_path(id: @topic.public_id, format: :rss)
    assert_response :not_found
    assert_not_includes response.body, "Secret archived content"
  end
end

class AdminModuleIsolationSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_user
    @staff.update!(account_type: :staff)
    grant_permission(@staff, "admin.access")
    grant_permission(@staff, "store.orders.read")
    grant_admin_module(@staff, "minecraft")
  end

  test "staff without store module cannot access store admin" do
    assert @staff.account_staff?, "fixture user must be staff account type"
    assert_not @staff.admin_module_allowed?("store")
    sign_in_as(@staff)
    get admin_store_orders_path
    assert_redirected_to admin_root_path
  end

  test "staff with minecraft module cannot access system settings even with system.settings.manage" do
    grant_permission(@staff, "system.settings.manage")
    sign_in_as(@staff)
    get admin_forum_settings_path
    assert_redirected_to admin_root_path
    get admin_store_settings_path
    assert_redirected_to admin_root_path
  end
end

class PasswordResetRateLimitSecurityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user(email: "reset-limit-#{SecureRandom.hex(4)}@example.com")
  end

  test "password reset request is rate limited per email and ip" do
    email = @user.email
    5.times do
      assert_enqueued_jobs 1, only: MailDeliveryJob do
        Identity::ResetPassword.call(email: email, ip_address: "203.0.113.10")
      end
      clear_enqueued_jobs
    end

    assert_no_enqueued_jobs only: MailDeliveryJob do
      result = Identity::ResetPassword.call(email: email, ip_address: "203.0.113.10")
      assert result.success?
    end
  end
end

class RegistrationRateLimitSecurityTest < ActiveSupport::TestCase
  test "registration is rate limited per ip" do
    5.times do |i|
      result = Identity::RegisterUser.call(
        email: "register-limit-#{i}-#{SecureRandom.hex(4)}@example.com",
        username: "reg#{SecureRandom.hex(4)}",
        password: "password123",
        ip_address: "203.0.113.20"
      )
      assert result.success?, result.error || result.errors
    end

    result = Identity::RegisterUser.call(
      email: "register-limit-blocked-#{SecureRandom.hex(4)}@example.com",
      username: "blocked#{SecureRandom.hex(4)}",
      password: "password123",
      ip_address: "203.0.113.20"
    )
    assert_not result.success?
    assert_includes result.error, "频繁"
  end
end

class SyncPresenceSkinUrlSecurityTest < ActiveSupport::TestCase
  setup do
    @server = Minecraft::Server.create!(
      name: "Skin Test",
      public_id: "srv_skin_#{SecureRandom.hex(4)}",
      connector_secret: "test-secret-#{SecureRandom.hex(16)}"
    )
    @uuid = SecureRandom.uuid
    @player_ref = ensure_connector_player_session!(server: @server, uuid: @uuid, username: "SkinPlayer")
    @player_ref.active_identity.update!(skin_texture_url: "https://textures.minecraft.net/texture/valid")
  end

  test "sync presence rejects private skin texture urls" do
    result = Minecraft::SyncPresence.call(
      server: @server,
      payload: {
        "uuid" => @uuid,
        "platform" => "java",
        "username" => "SkinPlayer",
        "event" => "player.quit",
        "skin_texture" => "http://169.254.169.254/latest/meta-data/"
      }
    )

    assert result.success?
    assert_equal "https://textures.minecraft.net/texture/valid", @player_ref.active_identity.reload.skin_texture_url
  end
end

class OpmlTokenExpirationSecurityTest < ActiveSupport::TestCase
  test "watching opml token expires after 90 days" do
    user = create_user
    token = Community::WatchingOpmlToken.generate(user)

    travel 91.days do
      assert_raises(Community::WatchingOpmlToken::InvalidToken) do
        Community::WatchingOpmlToken.verify(token)
      end
    end
  end

  test "search rss token expires after 90 days" do
    token = Community::SearchRssToken.generate("q" => "secret-topic")

    travel 91.days do
      assert_raises(Community::SearchRssToken::InvalidToken) do
        Community::SearchRssToken.verify(token)
      end
    end
  end
end

class AdminPrivilegeEscalationSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_user
    @staff.update!(account_type: :staff)
    grant_permission(@staff, "admin.access")
    grant_permission(@staff, "system.settings.manage")
    grant_admin_module(@staff, "system")
    @target = create_user
  end

  test "staff cannot assign roles without owner account" do
    owner_role = Role.find_or_create_by!(key: "test_owner_role") { |r| r.name = "Owner Role" }
    sign_in_as(@staff)
    patch admin_user_path(@target), params: { user: { role_ids: [ owner_role.id ], display_name: @target.display_name, locale: @target.locale, time_zone: @target.time_zone } }
    assert_redirected_to admin_user_path(@target)
    assert_not @target.reload.roles.include?(owner_role)
  end

  test "staff cannot change account type to owner" do
    sign_in_as(@staff)
    patch admin_user_path(@staff), params: { user: { account_type: "owner", display_name: @staff.display_name, locale: @staff.locale, time_zone: @staff.time_zone } }
    assert_redirected_to admin_user_path(@staff)
    assert_not @staff.reload.account_owner?
  end
end

class CouponEnumerationSecurityTest < ActiveSupport::TestCase
  setup do
    @coupon = Commerce::Coupon.create!(
      code: "ENUM#{SecureRandom.hex(3).upcase}",
      discount_type: "percentage",
      discount_value: 10,
      active: true
    )
  end

  test "preview coupon uses same error for missing and invalid codes" do
    @coupon.update!(min_amount_cents: 999_999)
    missing = Commerce::PreviewCoupon.call(subtotal_cents: 1000, code: "NOTREAL999", cart_items: [], user: nil)
    invalid = Commerce::PreviewCoupon.call(subtotal_cents: 1000, code: @coupon.code, cart_items: [], user: nil)

    assert_equal I18n.t("mcweb.services.errors.coupon_unavailable"), missing.error
    assert_equal I18n.t("mcweb.services.errors.coupon_unavailable"), invalid.error
  end

  test "apply coupon uses same error for missing and invalid codes" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_enum_#{SecureRandom.hex(4)}",
      order_number: "ORD-ENUM-#{SecureRandom.hex(4)}",
      user: user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )
    @coupon.update!(min_amount_cents: 999_999)

    missing = Commerce::ApplyCoupon.call(order: order, code: "NOTREAL999")
    invalid = Commerce::ApplyCoupon.call(order: order, code: @coupon.code)

    assert_equal I18n.t("mcweb.services.errors.coupon_unavailable"), missing.error
    assert_equal I18n.t("mcweb.services.errors.coupon_unavailable"), invalid.error
  end
end

class ApplyGiftCardEnumerationSecurityTest < ActiveSupport::TestCase
  setup do
    @card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.hex(4).upcase}",
      initial_balance_cents: 1000,
      balance_cents: 1000,
      currency: "CNY",
      active: true
    )
  end

  test "apply gift card uses same error for missing and inactive codes" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_gc_enum_#{SecureRandom.hex(4)}",
      order_number: "ORD-GC-ENUM-#{SecureRandom.hex(4)}",
      user: user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )
    @card.update!(active: false)

    missing = Commerce::ApplyGiftCard.call(order: order, code: "NOTREAL999")
    invalid = Commerce::ApplyGiftCard.call(order: order, code: @card.code)

    assert_equal I18n.t("mcweb.services.errors.gift_card_unavailable"), missing.error
    assert_equal I18n.t("mcweb.services.errors.gift_card_unavailable"), invalid.error
  end

  test "apply gift card uses same error for zero balance" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_gc_zero_#{SecureRandom.hex(4)}",
      order_number: "ORD-GC-ZERO-#{SecureRandom.hex(4)}",
      user: user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )
    @card.update!(balance_cents: 0)

    missing = Commerce::ApplyGiftCard.call(order: order, code: "NOTREAL999")
    zero_balance = Commerce::ApplyGiftCard.call(order: order, code: @card.code)

    assert_equal missing.error, zero_balance.error
  end
end

class ClaimGiftCardEnumerationSecurityTest < ActiveSupport::TestCase
  test "claim gift card uses same error for missing and inactive codes" do
    user = create_user
    inactive = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.hex(4).upcase}",
      initial_balance_cents: 500,
      balance_cents: 500,
      currency: "CNY",
      active: false
    )

    missing = Commerce::ClaimGiftCard.call(user: user, gift_card: nil)
    invalid = Commerce::ClaimGiftCard.call(user: user, gift_card: inactive)

    assert_equal I18n.t("mcweb.services.errors.gift_card_unavailable"), missing.error
    assert_equal I18n.t("mcweb.services.errors.gift_card_unavailable"), invalid.error
  end

  test "claim gift card uses same error when owned by another user" do
    owner = create_user
    claimant = create_user(username: "gc_claim_#{SecureRandom.hex(4)}")
    card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.hex(4).upcase}",
      initial_balance_cents: 500,
      balance_cents: 500,
      currency: "CNY",
      active: true,
      owner_user: owner
    )

    result = Commerce::ClaimGiftCard.call(user: claimant, gift_card: card)

    assert result.failure?
    assert_equal I18n.t("mcweb.services.errors.gift_card_unavailable"), result.error
  end
end

class PreviewStoreCreditReservedSecurityTest < ActiveSupport::TestCase
  test "preview store credit respects pending order reservation" do
    user = create_user
    user.update!(store_credit_cents: 1000)
    Commerce::Order.create!(
      public_id: "ord_sc_prev_#{SecureRandom.hex(4)}",
      order_number: "ORD-SC-PREV-#{SecureRandom.hex(4)}",
      user: user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 200,
      store_credit_amount_cents: 800,
      discount_cents: 0,
      currency: "CNY"
    )

    result = Commerce::PreviewStoreCredit.call(
      user: user,
      subtotal_cents: 500,
      discount_cents: 0,
      shipping_cents: 0,
      gift_wrap_cents: 0,
      gift_card_amount_cents: 0
    )

    assert result.success?
    assert_equal 1000, result.value[:balance_cents]
    assert_equal 200, result.value[:available_balance_cents]
    assert_equal 200, result.value[:store_credit_amount_cents]
    assert_equal 300, result.value[:total_cents]
  end
end

class CreateOrderCartAuthorizationSecurityTest < ActiveSupport::TestCase
  test "create order rejects another users cart" do
    owner = create_user
    attacker = create_user(username: "cart_att_#{SecureRandom.hex(4)}")
    cart = Commerce::Cart.create!(user: owner)
    product = Commerce::Product.create!(
      name: "Cart Auth Product",
      slug: "cart-auth-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    cart.add_item!(product: product, quantity: 1)

    result = Commerce::CreateOrder.call(cart: cart, user: attacker)

    assert result.failure?
    assert_equal I18n.t("mcweb.services.errors.cart_unauthorized"), result.error
  end
end

class RssLoginRequiredSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "rss-login-cat-#{SecureRandom.hex(3)}") { |c| c.name = "RSS Login" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "rss-login-sec-#{SecureRandom.hex(3)}") do |s|
      s.name = "Members Only"
      s.position = 0
      s.login_required = true
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Secret members topic #{SecureRandom.hex(4)}",
      body: "Hidden from anonymous RSS",
      ip_address: "127.0.0.1"
    ).value
    @token = Community::SearchRssToken.generate("q" => @topic.title)
  end

  test "ad hoc search rss hides login required topics" do
    get forum_search_rss_path(q: @topic.title, token: @token, format: :rss)
    assert_response :success
    assert_not_includes response.body, "<item>"
    assert_not_includes response.body, "Hidden from anonymous RSS"
  end
end

class DatabaseHostSafetyTest < ActiveSupport::TestCase
  test "rejects cloud metadata host" do
    assert_not Mcweb::DatabaseHostSafety.allowed?("169.254.169.254")
  end

  test "allows localhost" do
    assert Mcweb::DatabaseHostSafety.allowed?("localhost")
    assert Mcweb::DatabaseHostSafety.allowed?("127.0.0.1")
  end
end

class OwnerProtectionSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @owner.update!(account_type: :owner)
    grant_permission(@owner, "admin.access")

    @admin = create_user
    @admin.update!(account_type: :staff)
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    grant_admin_module(@admin, "system")
  end

  test "non owner admin cannot ban site owner" do
    sign_in_as(@admin)
    post ban_admin_user_path(@owner), params: { reason: "test" }
    assert_redirected_to admin_user_path(@owner)
    assert_not @owner.reload.banned?
  end
end

class CouponPublicEnumerationSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @coupon = Commerce::Coupon.create!(
      code: "PUB#{SecureRandom.hex(3).upcase}",
      discount_type: "percentage",
      discount_value: 10,
      active: true
    )
  end

  test "coupon show does not reveal discount details" do
    get store_coupon_path(code: @coupon.code)
    assert_response :success
    assert_not_includes response.body, "percentage"
    assert_not_includes response.body, '"available":true'
  end

  test "coupon onebox does not expose codes" do
    result = Community::FetchCouponOnebox.call(url: "/app/store/coupons/#{@coupon.code}")
    assert_nil result.value
  end
end

class StaffModuleGrantSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @owner.update!(account_type: :owner)
    grant_permission(@owner, "admin.access")

    @staff = create_user
    @staff.update!(account_type: :staff)
    grant_permission(@staff, "admin.access")
    grant_permission(@staff, "system.settings.manage")
    grant_admin_module(@staff, "system")
  end

  test "staff cannot grant themselves store module" do
    sign_in_as(@staff)
    patch admin_user_path(@staff), params: {
      user: {
        display_name: @staff.display_name,
        locale: @staff.locale,
        time_zone: @staff.time_zone,
        admin_modules: %w[system store]
      }
    }
    assert_redirected_to admin_user_path(@staff)
    assert_not @staff.admin_module_grants.exists?(module_key: "store")
  end
end

class SidekiqWebConstraintSecurityTest < ActiveSupport::TestCase
  test "minecraft only staff cannot access sidekiq web" do
    user = create_user
    user.update!(account_type: :staff)
    grant_permission(user, "admin.access")
    grant_permission(user, "system.jobs.read")
    grant_admin_module(user, "minecraft")

    assert_not user.admin_module_allowed?("system")
  end
end

class GiftCardEnumerationSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.hex(4).upcase}",
      initial_balance_cents: 5000,
      balance_cents: 5000,
      currency: "CNY",
      active: true
    )
  end

  test "gift card show does not reveal redeemable valid cards" do
    get store_gift_card_path(code: @card.code)
    assert_response :success
    assert_not_includes response.body, '"redeemable":true'
    assert_not_includes response.body, "redeemable\":true"
  end

  test "apply invalid gift card shows alert not success" do
    user = create_user
    sign_in_as(user)
    @card.update!(active: false)

    post store_apply_gift_card_path(code: @card.code)
    assert_redirected_to store_cart_path
    follow_redirect!
    assert_includes response.body, I18n.t("mcweb.services.errors.gift_card_unavailable")
    assert_not_includes response.body, I18n.t("mcweb.flash.gift_card_updated")
  end
end

class LoginEnumerationSecurityTest < ActiveSupport::TestCase
  test "banned user gets generic login failure" do
    user = create_user
    user.ban!(reason: "test")

    result = Identity::AuthenticateUser.call(
      email: user.email,
      password: "password123",
      ip_address: "203.0.113.50"
    )

    assert_not result.success?
    assert_equal "邮箱或密码错误。", result.error
  end
end

class ForumEventWebhookRetrySecurityTest < ActiveSupport::TestCase
  test "admin retry rejects private webhook urls" do
    delivery = Community::EventWebhookDelivery.create!(
      event_type: "topic.created",
      url: "http://127.0.0.1/hook",
      status: "failed",
      request_payload: { "event" => "topic.created" },
      attempt_count: 1
    )

    result = Community::AdminRetryForumEventWebhook.call(delivery: delivery)
    assert_not result.success?
    assert_includes result.error.to_s, "内网"
  end
end

class WhisperPostSecurityTest < ActiveSupport::TestCase
  setup do
    @staff = create_user
    grant_permission(@staff, "forum.topics.lock")
    @member = create_user
    category = Community::Category.find_or_create_by!(slug: "whisper-sec-#{SecureRandom.hex(3)}") { |c| c.name = "Whisper" }
    section = Community::Section.find_or_create_by!(category: category, slug: "whisper-sec-#{SecureRandom.hex(3)}") do |s|
      s.name = "Whisper"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @member,
      section: section,
      title: "Whisper topic #{SecureRandom.hex(4)}",
      body: "Public post",
      ip_address: "127.0.0.1"
    ).value
    @whisper = Community::CreatePost.call(
      user: @staff,
      topic: @topic,
      body: "Secret staff whisper content",
      whisper: true,
      ip_address: "127.0.0.1"
    ).value
  end

  test "members cannot read whisper posts via post access" do
    assert_not Community::PostAccess.readable?(post: @whisper, user: @member)
  end

  test "staff with lock permission can read whisper posts" do
    assert Community::PostAccess.readable?(post: @whisper, user: @staff)
  end
end

class CartRecoveryHijackSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @attacker = create_user
    @cart = Commerce::Cart.create!(user: @owner)
    product = Commerce::Product.create!(
      name: "Victim Item",
      slug: "victim-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    @cart.add_item!(product: product, quantity: 1)
    @cart.ensure_recovery_token!
  end

  test "anonymous user can recover own cart via emailed recovery token" do
    get store_cart_path(recovery: @cart.recovery_token)
    assert_response :success
    assert_includes response.body, "Victim Item"
    assert_includes response.body, '"cartRecovered":true'
  end

  test "other logged in user cannot recover victims cart via token" do
    sign_in_as(@attacker)
    get store_cart_path(recovery: @cart.recovery_token)
    assert_response :success
    assert_not_includes response.body, "Victim Item"
  end

  test "anonymous recovery token cannot modify victims cart" do
    get store_cart_path(recovery: @cart.recovery_token)
    assert_response :success

    delete clear_store_cart_path
    assert_redirected_to store_cart_path
    follow_redirect!
    assert_includes response.body, "请先登录"
    assert @cart.reload.items.exists?
  end
end

class ValidateExecCommandProductionSecurityTest < ActiveSupport::TestCase
  test "empty exec prefix whitelist is denied in production" do
    SiteSetting.set("minecraft.exec_command.allowed_prefixes", "")
    production_env = ActiveSupport::EnvironmentInquirer.new("production")
    singleton = class << Rails; self; end
    original_env = Rails.env
    singleton.define_method(:env) { production_env }
    begin
      result = Minecraft::ValidateExecCommand.call(command: "rm -rf /")
      assert result.failure?
      assert_includes result.error, "not configured"
    ensure
      singleton.define_method(:env) { original_env }
    end
  end
end

class CheckoutStoreCreditPreviewSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(store_credit_cents: 5000)
    @product = Commerce::Product.create!(
      name: "Preview Item",
      slug: "preview-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    cart = Commerce::Cart.find_or_create_by!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
    @valid_coupon = Commerce::Coupon.create!(
      code: "VALID#{SecureRandom.hex(3).upcase}",
      discount_type: "fixed",
      discount_value: 500,
      active: true
    )
    @invalid_coupon = "INVALID#{SecureRandom.hex(3).upcase}"
    sign_in_as(@user)
  end

  test "preview store credit ignores arbitrary coupon codes in request body" do
    post preview_store_credit_store_checkout_path,
         params: { coupon_code: @valid_coupon.code },
         as: :json
    assert_response :success
    without_session = JSON.parse(response.body)
    assert_equal 1000, without_session["store_credit_amount_cents"].to_i

    post preview_coupon_store_checkout_path,
         params: { code: @valid_coupon.code },
         as: :json
    assert_response :success

    post preview_store_credit_store_checkout_path,
         params: { coupon_code: @invalid_coupon },
         as: :json
    assert_response :success
    with_session = JSON.parse(response.body)
    assert_equal 500, with_session["store_credit_amount_cents"].to_i
  end

  test "checkout create ignores coupon codes submitted in form params" do
    assert_difference -> { Commerce::Order.count }, 1 do
      post store_checkout_path,
           params: {
             checkout: {
               provider: "fake",
               coupon_code: @valid_coupon.code
             }
           }
    end

    order = Commerce::Order.order(:id).last
    assert_equal 0, order.discount_cents
    assert_equal 1000, order.total_cents
  end
end

class SavedSearchWebhookDeliverySecurityTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @other = create_user
    @search = Community::SavedSearch.create!(
      user: @owner,
      name: "Webhook search",
      query: "test",
      filters: {}
    )
    @delivery = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/hook",
      status: "failed",
      request_payload: { "event" => "saved_search.match" },
      attempt_count: 1
    )
  end

  test "other user cannot retry someone elses webhook delivery" do
    sign_in_as(@other)
    post forum_retry_saved_search_webhook_delivery_path(@delivery)
    assert_response :not_found
  end
end

class CouponUrlRateLimitSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @coupon = Commerce::Coupon.create!(
      code: "URL#{SecureRandom.hex(3).upcase}",
      discount_type: "fixed",
      discount_value: 100,
      active: true
    )
    @product = Commerce::Product.create!(
      name: "Coupon URL Item",
      slug: "curl-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    patch store_cart_path, params: { product_id: @product.public_id, quantity: 1 }
  end

  test "cart coupon url param stops applying after rate limit" do
    31.times { |i| get store_cart_path(coupon: "TRY#{i}") }
    get store_cart_path(coupon: @coupon.code)
    assert_response :success
    assert_not_includes response.body, %("pendingCouponCode":"#{@coupon.code}")
    assert_not_includes response.body, %("pendingCouponCode": "#{@coupon.code}")
  end
end

class VerifyEmailRateLimitSecurityTest < ActionDispatch::IntegrationTest
  test "email verification requests are rate limited per ip" do
    31.times { |i| get identity_email_verification_path(token: "invalid-#{i}") }

    user = create_user(email_verified: false)
    token = user.generate_email_verification_token!
    get identity_email_verification_path(token: token)

    assert_redirected_to root_path
    assert_not user.reload.email_verified?
  end
end
