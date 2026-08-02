# frozen_string_literal: true

require "test_helper"

class RecipientLocaleNotificationsTest < ActiveSupport::TestCase
  setup do
    @english_user = create_user(locale: "en")
    @chinese_user = create_user(locale: "zh-CN")
  end

  test "commerce jobs persist copy in each recipient locale instead of the ambient locale" do
    english = create_price_drop_notification(@english_user, ambient_locale: "zh-CN")
    chinese = create_price_drop_notification(@chinese_user, ambient_locale: "en")

    assert_equal "Price drop", english.title
    assert_includes english.body, "EUR 8.00"
    refute_match(/\p{Han}/, english.title)
    assert_equal "商品降价了", chinese.title
    assert_includes chinese.body, "现价"
  end

  test "deferred order-event copy resolves inside the recipient locale" do
    notification = I18n.with_locale("zh-CN") do
      Commerce::NotifyOrderEvent.call(
        user: @english_user,
        notification_type: "commerce.refund_rejected",
        title: -> { I18n.t("mcweb.labels.notification_types.commerce.refund_rejected") },
        body: -> { I18n.t("mcweb.mail.commerce.refund_rejected.body", number: "ORDER-1") },
        path: "/app/store/orders/order_1"
      )
      @english_user.notifications.where(notification_type: "commerce.refund_rejected").last
    end

    assert_equal "Refund rejected", notification.title
    assert_includes notification.body, "ORDER-1"
    refute_match(/\p{Han}/, notification.body)
  end

  test "forum notifications resolve full keys and deferred site-wide labels for the recipient" do
    english_mute = create_sitewide_mute(@english_user, ambient_locale: "zh-CN")
    chinese_mute = create_sitewide_mute(@chinese_user, ambient_locale: "en")

    assert_equal "You have been muted", english_mute.title
    assert_includes english_mute.body, "Entire site"
    assert_equal "你已被禁言", chinese_mute.title
    assert_includes chinese_mute.body, "全站"

    approved = I18n.with_locale("zh-CN") do
      Community::InAppNotification.notify(
        user: @english_user,
        notification_type: "forum.post_approved",
        key: "post_approved",
        title_key: "mcweb.labels.notification_types.forum.post_approved",
        body_key: "mcweb.labels.notification_bodies.forum.post_approved",
        title: "Locale topic",
        metadata: { path: "/app/forum/topics/topic_1" }
      )
    end

    assert_equal "Post approved", approved.title
    assert_equal "Your post in «Locale topic» was approved.", approved.body
  end

  private

  def create_price_drop_notification(user, ambient_locale:)
    product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Locale product",
      slug: "locale-price-#{SecureRandom.hex(5)}",
      product_type: "virtual",
      status: "active",
      price_cents: 800,
      currency: "EUR",
      stock: 5
    )
    Commerce::PriceAlert.create!(user: user, product: product, baseline_price_cents: 1_000)
    NotificationPreference.set!(user, channel: "in_app", notification_type: "commerce.price_drop", enabled: true)
    NotificationPreference.set!(user, channel: "email", notification_type: "commerce.price_drop", enabled: false)

    I18n.with_locale(ambient_locale) do
      Commerce::NotifyPriceDropJob.perform_now(product.id)
    end
    user.notifications.where(notification_type: "commerce.price_drop").last
  end

  def create_sitewide_mute(user, ambient_locale:)
    moderator = create_user
    grant_permission(moderator, "forum.users.mute")
    NotificationPreference.set!(user, channel: "in_app", notification_type: "forum.silenced", enabled: true)

    I18n.with_locale(ambient_locale) do
      result = Community::CreateMute.call(actor: moderator, user: user, reason: "Locale reason")
      assert_predicate result, :success?
    end
    user.notifications.where(notification_type: "forum.silenced").last
  end
end
