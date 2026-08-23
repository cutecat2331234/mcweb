# frozen_string_literal: true

require "test_helper"

class UserFacingMailerI18nTest < ActionMailer::TestCase
  IDENTITY_SUBJECTS = %w[
    verification password_reset password_changed totp_enabled totp_recovery
    email_change_confirmation email_change_security_notice
  ].freeze
  FORUM_SUBJECTS = %w[
    topic_reply private_message conversation_invitation mention here section_topic tag_topic
    followed_topic followed_reply digest saved_search_digest post_edited
    bookmark_reminder user_warning badge_earned topic_assigned trust_level_up
    post_reaction post_quoted topic_solved topic_invite poll_closed
  ].freeze
  COMMERCE_SUBJECTS = %w[
    order_created payment_reminder payment_confirmed order_cancelled
    refund_processed refund_rejected order_processing order_fulfilling
    order_completed refund_requested price_drop order_fulfilled order_shipped
    question_answered product_changelog new_product_question merchant_review_reply
    review_request stock_restocked product_available gift_card_created
    gift_card_expiry gift_card_purchased abandoned_cart_first abandoned_cart_second
  ].freeze

  setup do
    @english_user = create_user(locale: "en")
    @chinese_user = create_user(locale: "zh-CN")
    @author = create_user
  end

  test "identity mail renders subject and body in each recipient locale" do
    english = Identity::Mailer.verification_email(@english_user.id, "english-token")
    chinese = Identity::Mailer.verification_email(@chinese_user.id, "chinese-token")

    assert_equal "Verify your McWeb email address", english.subject
    assert_includes decoded_body(english), "Please verify your email address"
    assert_equal "请验证您的 McWeb 邮箱", chinese.subject
    assert_includes decoded_body(chinese), "请点击以下链接验证您的邮箱地址"
  end

  test "password-change security notice is localized and includes revocation guidance" do
    changed_at = Time.zone.parse("2026-08-21 12:30:00")
    english = Identity::Mailer.password_changed_email(@english_user.id, changed_at.iso8601, 2)
    chinese = Identity::Mailer.password_changed_email(@chinese_user.id, changed_at.iso8601, 1)

    assert_equal "Your McWeb password was changed", english.subject
    assert_includes decoded_body(english), "2 other signed-in sessions were revoked"
    assert_includes decoded_body(english), "Reset password"
    assert_equal "您的 McWeb 密码已修改", chinese.subject
    assert_includes decoded_body(chinese), "已撤销 1 个其他登录会话"
    assert_includes decoded_body(chinese), "重置密码"
  end

  test "two-factor enrollment security notice is localized and includes recovery guidance" do
    enabled_at = Time.zone.parse("2026-08-24 12:30:00")
    english = Identity::Mailer.totp_enabled_email(@english_user.id, enabled_at.iso8601, 2)
    chinese = Identity::Mailer.totp_enabled_email(@chinese_user.id, enabled_at.iso8601, 1)

    assert_equal "Two-factor authentication was enabled on your McWeb account", english.subject
    assert_includes decoded_body(english), "2 other signed-in sessions were revoked"
    assert_includes decoded_body(english), "Recover two-factor authentication"
    assert_includes decoded_body(english), "Reset password"
    assert_equal "您的 McWeb 账户已启用两步验证", chinese.subject
    assert_includes decoded_body(chinese), "已撤销 1 个其他登录会话"
    assert_includes decoded_body(chinese), "恢复两步验证"
    assert_includes decoded_body(chinese), "重置密码"
  end

  test "email-change confirmation and old-address security notice use the account locale" do
    token = SecureRandom.urlsafe_base64(32)
    revocation_token = SecureRandom.urlsafe_base64(32)
    request_record = Identity::EmailChangeRequest.create!(
      user: @english_user,
      original_email: @english_user.email,
      requested_email: "replacement@example.com",
      original_email_verified: true,
      original_email_verified_at: @english_user.email_verified_at,
      confirmation_token: token,
      confirmation_token_digest: Digest::SHA256.hexdigest(token),
      revocation_token:,
      revocation_token_digest: Digest::SHA256.hexdigest(revocation_token),
      requested_at: Time.current,
      expires_at: 24.hours.from_now
    )

    confirmation = Identity::Mailer.email_change_confirmation(request_record.id, token)
    notice = Identity::Mailer.email_change_security_notice(request_record.id, revocation_token)

    assert_equal [ "replacement@example.com" ], confirmation.to
    assert_equal "Confirm your new McWeb email address", confirmation.subject
    assert_includes decoded_body(confirmation), "current email remains active"
    assert_equal [ @english_user.email ], notice.to
    assert_equal "Security notice: McWeb email change requested", notice.subject
    assert_includes decoded_body(notice), "replacement@example.com"
    assert_includes decoded_body(notice), "reset your password"
  end

  test "forum mail renders subject and body in each recipient locale" do
    topic, post = create_forum_reply

    english = Community::ForumMailer.topic_reply(@english_user.id, topic.public_id, post.id)
    chinese = Community::ForumMailer.topic_reply(@chinese_user.id, topic.public_id, post.id)

    assert_equal "New reply: Localized topic", english.subject
    assert_includes decoded_body(english), "replied in topic"
    assert_equal "主题有新回复：Localized topic", chinese.subject
    assert_includes decoded_body(chinese), "在主题「Localized topic」中回复了"
  end

  test "trust-level mail localizes the level from its numeric key" do
    english = Community::ForumMailer.trust_level_up(@english_user.id, 2)
    chinese = Community::ForumMailer.trust_level_up(@chinese_user.id, 2)

    assert_equal "Trust level increased: Member", english.subject
    assert_includes decoded_body(english), "Member (Lv.2)"
    refute_match(/\p{Han}/, decoded_body(english))
    assert_equal "信任等级提升：成员", chinese.subject
    assert_includes decoded_body(chinese), "成员（Lv.2）"
  end

  test "digest notification copy and rendered mail follow each recipient locale" do
    english_notification = create_trust_level_notification(@english_user, ambient_locale: "zh-CN")
    chinese_notification = create_trust_level_notification(@chinese_user, ambient_locale: "en")

    assert_equal "Trust level up: Member", english_notification.title
    assert_equal "信任等级提升：成员", chinese_notification.title

    english = Community::ForumMailer.digest(@english_user.id, [ english_notification.id ])
    chinese = Community::ForumMailer.digest(@chinese_user.id, [ chinese_notification.id ])

    assert_equal "Forum digest — 1 new notification", english.subject
    assert_includes decoded_body(english), "Here is your forum digest (1 notification):"
    assert_includes decoded_body(english), "Trust level up: Member"
    assert_includes decoded_body(english), "You reached trust level 2"
    refute_match(/\p{Han}/, decoded_body(english))
    assert_equal "论坛摘要 — 1 条新动态", chinese.subject
    assert_includes decoded_body(chinese), "以下是您订阅的论坛摘要（1 条）："
    assert_includes decoded_body(chinese), "信任等级提升：成员"
    assert_includes decoded_body(chinese), "你已达到信任等级 2"

    second_english_notification = create_trust_level_notification(@english_user, ambient_locale: "zh-CN")
    plural = Community::ForumMailer.digest(
      @english_user.id,
      [ english_notification.id, second_english_notification.id ]
    )
    assert_equal "Forum digest — 2 new notifications", plural.subject
    assert_includes decoded_body(plural), "Here is your forum digest (2 notifications):"
  end

  test "saved-search digest uses singular and plural topic copy" do
    first_topic, = create_forum_reply
    second_topic, = create_forum_reply
    search = Community::SavedSearch.create!(
      user: @english_user,
      name: "Release notes",
      query: "",
      filters: {},
      notify_daily: true
    )

    singular = Community::ForumMailer.saved_search_digest(search.id, [ first_topic.id ])
    plural = Community::ForumMailer.saved_search_digest(search.id, [ first_topic.id, second_topic.id ])

    assert_includes CGI.unescapeHTML(decoded_body(singular)), 'Your saved search "Release notes" has 1 new topic:'
    assert_includes CGI.unescapeHTML(decoded_body(plural)), 'Your saved search "Release notes" has 2 new topics:'
  end

  test "order and refund mail derive locale from their associated order user" do
    english_order = create_order(@english_user, number: "EN-ORDER")
    chinese_order = create_order(@chinese_user, number: "ZH-ORDER")
    [ @english_user, @chinese_user ].each do |user|
      NotificationPreference.set!(user, channel: "email", notification_type: "commerce.order_created", enabled: true)
      NotificationPreference.set!(user, channel: "email", notification_type: "commerce.refund_processed", enabled: true)
    end

    english_created = Commerce::OrderMailer.order_created(english_order.id)
    chinese_created = Commerce::OrderMailer.order_created(chinese_order.id)
    assert_equal "Order confirmation EN-ORDER", english_created.subject
    assert_includes decoded_body(english_created), "Order notification"
    assert_includes decoded_body(english_created), "Status: Paid"
    refute_includes decoded_body(english_created), "Status: paid"
    assert_equal "订单确认 ZH-ORDER", chinese_created.subject
    assert_includes decoded_body(chinese_created), "订单通知"

    refund = create_refund(english_order)
    refund_mail = Commerce::OrderMailer.refund_processed(refund.id)
    assert_equal "Refund processed for order EN-ORDER", refund_mail.subject
    assert_includes decoded_body(refund_mail), "A refund has been processed for order EN-ORDER"
  end

  test "stock and gift-card mail localize variants and preserve the actual currency" do
    product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Potion",
      slug: "potion-#{SecureRandom.hex(5)}",
      product_type: "virtual",
      status: "active",
      price_cents: 2_500,
      currency: "USD",
      stock: 5
    )
    variant = Commerce::ProductVariant.create!(
      product: product,
      name: "Large",
      sku: "SKU-#{SecureRandom.hex(5)}",
      price_cents: 2_500,
      stock: 5
    )
    alert = Commerce::StockAlert.create!(user: @english_user, product: product, variant: variant)
    stock_mail = Commerce::StockMailer.restocked(alert.id)

    assert_includes decoded_body(stock_mail), 'Product "Potion" (Large) you watched is back in stock.'
    refute_includes decoded_body(stock_mail), "（"

    order = create_order(@english_user, number: "USD-GIFT")
    order.update!(currency: "USD")
    card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.hex(5).upcase}",
      owner_user: @english_user,
      balance_cents: 2_500,
      initial_balance_cents: 2_500,
      currency: "USD",
      active: true
    )
    gift_mail = Commerce::GiftCardMailer.gift_card_purchased(order.id, [ card.id ])
    gift_body = decoded_body(gift_mail)

    assert_includes gift_body, "Value: USD 25.00"
    refute_includes gift_body, "¥"
  end

  test "created gift-card mail normalizes the recipient before locale lookup and delivery" do
    card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.hex(5).upcase}",
      balance_cents: 2_500,
      initial_balance_cents: 2_500,
      currency: "EUR",
      active: true
    )

    mail = Commerce::GiftCardMailer.gift_card_created(card.id, "  #{@english_user.email.upcase}  ")

    assert_equal [ @english_user.email.downcase ], mail.to
    assert_equal "You received a gift card: #{card.code}", mail.subject
    assert_includes decoded_body(mail), "Your gift card has been created"
    refute_match(/\p{Han}/, decoded_body(mail))
  end

  test "order and product mail render exact ISO currencies beyond CNY and USD" do
    order = create_order(@english_user, number: "EUR-ORDER")
    order.update!(currency: "EUR")
    Commerce::OrderItem.create!(
      order: order,
      product_name: "Euro item",
      quantity: 1,
      unit_price_cents: 1_000,
      total_cents: 1_000
    )
    NotificationPreference.set!(
      @english_user,
      channel: "email",
      notification_type: "commerce.order_created",
      enabled: true
    )

    order_mail = Commerce::OrderMailer.order_created(order.id)
    assert_includes decoded_body(order_mail), "EUR 10.00"
    refute_includes decoded_body(order_mail), "$10.00"

    product = create_product(name: "Sterling product", currency: "GBP", price_cents: 2_000)
    NotificationPreference.set!(
      @english_user,
      channel: "email",
      notification_type: "commerce.price_drop",
      enabled: true
    )
    price_mail = Commerce::OrderMailer.price_drop(@english_user.id, product.id, 3_000, 2_000)
    price_body = decoded_body(price_mail)
    assert_includes price_body, "GBP 30.00"
    assert_includes price_body, "GBP 20.00"
    refute_includes price_body, "$30.00"
  end

  test "merchant review reply renders the persisted merchant reply" do
    product = create_product(name: "Reviewed product", currency: "EUR")
    review = Commerce::Review.create!(
      user: @english_user,
      product: product,
      rating: 5,
      status: "published",
      merchant_reply: "Thank you for the detailed review."
    )
    NotificationPreference.set!(
      @english_user,
      channel: "email",
      notification_type: "commerce.merchant_review_reply",
      enabled: true
    )

    mail = Commerce::OrderMailer.merchant_review_reply(review.id)

    assert_equal "Seller replied to your review of Reviewed product", mail.subject
    assert_includes decoded_body(mail), "Thank you for the detailed review."
  end

  test "system alert subject and body use the requested locale" do
    mail = Administration::SystemMailer.webhook_failure_alert(
      to: "operator@example.com",
      forum_failed: 6,
      store_failed: 0,
      forum_threshold: 5,
      store_threshold: 5,
      forum_alert: true,
      store_alert: false,
      stats: { forum: { total: 10 }, store: { total: 2 } },
      locale: "en"
    )

    assert_equal "[McWeb] Webhook delivery failure alert (24 hours)", mail.subject
    assert_includes decoded_body(mail), "Webhook failures in the last 24 hours"
    refute_match(/\p{Han}/, decoded_body(mail))
  end

  test "every inventoried user-facing subject exists in both locales" do
    {
      "mcweb.mail.identity.subjects" => IDENTITY_SUBJECTS,
      "mcweb.mail.forum.subjects" => FORUM_SUBJECTS,
      "mcweb.mail.commerce.subjects" => COMMERCE_SUBJECTS
    }.each do |prefix, names|
      names.each do |name|
        %w[en zh-CN].each do |locale|
          assert I18n.exists?("#{prefix}.#{name}", locale), "Missing #{locale} translation for #{prefix}.#{name}"
        end
      end
    end
  end

  test "user-facing mailers do not contain hard-coded Chinese copy" do
    sources = [
      Rails.root.join("app/mailers/administration/system_mailer.rb"),
      Rails.root.join("app/mailers/identity/mailer.rb"),
      Rails.root.join("app/mailers/community/forum_mailer.rb"),
      *Rails.root.glob("app/mailers/commerce/*_mailer.rb")
    ]
    templates = [
      *Rails.root.glob("app/views/administration/system_mailer/**/*.erb"),
      *Rails.root.glob("app/views/identity/mailer/**/*.erb"),
      *Rails.root.glob("app/views/community/forum_mailer/**/*.erb"),
      *Rails.root.glob("app/views/commerce/*_mailer/**/*.erb")
    ]
    copy = (sources + templates).map(&:read).join("\n")

    refute_match(/\p{Han}/, copy)
  end

  private

  def decoded_body(email)
    [ email.text_part&.body&.decoded, email.html_part&.body&.decoded, email.body.decoded ].compact.join("\n")
  end

  def create_forum_reply
    category = Community::Category.create!(name: "Localized", slug: "localized-#{SecureRandom.hex(5)}")
    section = Community::Section.create!(
      category: category,
      name: "Localized",
      slug: "localized-section-#{SecureRandom.hex(5)}",
      position: 0
    )
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Localized topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 1
    )
    post = Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: 2,
      body: "Localized reply body",
      status: "published"
    )
    [ topic, post ]
  end

  def create_trust_level_notification(user, ambient_locale:)
    NotificationPreference.set!(user, channel: "email", notification_type: "forum.trust_level", enabled: false)
    NotificationPreference.set!(user, channel: "in_app", notification_type: "forum.trust_level", enabled: true)

    I18n.with_locale(ambient_locale) do
      Community::NotifyTrustLevelUp.call(user: user, level: 2)
    end
    user.notifications.where(notification_type: "forum.trust_level").order(:id).last
  end

  def create_order(user, number:)
    Commerce::Order.create!(
      public_id: "order_#{SecureRandom.alphanumeric(16)}",
      user: user,
      order_number: number,
      status: "paid",
      subtotal_cents: 1_000,
      discount_cents: 0,
      total_cents: 1_000,
      currency: "CNY"
    )
  end

  def create_product(name:, currency:, price_cents: 1_000)
    Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: name,
      slug: "mail-product-#{SecureRandom.hex(5)}",
      product_type: "virtual",
      status: "active",
      price_cents: price_cents,
      currency: currency,
      stock: 5
    )
  end

  def create_refund(order)
    payment = Payments::Record.create!(
      order: order,
      provider: "fake",
      amount_cents: order.total_cents,
      currency: order.currency,
      status: "succeeded"
    )
    Commerce::Refund.create!(
      order: order,
      payment_record: payment,
      status: "completed",
      amount_cents: order.total_cents,
      reason: "Localized refund"
    )
  end
end
