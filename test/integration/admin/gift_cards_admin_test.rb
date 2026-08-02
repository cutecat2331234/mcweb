# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class GiftCardsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @staff = create_user(account_type: "staff")
      grant_permission(@staff, "admin.access")
      grant_permission(@staff, "store.products.manage")
      grant_admin_module(@staff, "store")
      sign_in_as(@staff)
    end

    test "create normalizes the optional recipient and enqueues delivery after persistence" do
      captured = []

      assert_difference("Commerce::GiftCard.count", 1) do
        MailDeliveryJob.stub(:perform_later, ->(*args, **kwargs) { captured << [ args, kwargs ] }) do
          post admin_store_gift_cards_path, params: {
            gift_card: valid_attributes.merge(recipient_email: "  Recipient@Example.COM  ")
          }
        end
      end

      card = Commerce::GiftCard.order(:id).last
      assert_redirected_to admin_store_gift_card_path(card)
      assert_equal @staff, card.created_by
      assert_equal card.balance_cents, card.initial_balance_cents
      assert_equal [
        [
          [ "Commerce::GiftCardMailer", "gift_card_created", "deliver_now" ],
          { args: [ card.id, "recipient@example.com" ] }
        ]
      ], captured
    end

    test "create rejects an invalid recipient without persisting or enqueuing mail" do
      assert_no_difference("Commerce::GiftCard.count") do
        MailDeliveryJob.stub(:perform_later, ->(*) { flunk("invalid recipients must not enqueue mail") }) do
          post admin_store_gift_cards_path, params: {
            gift_card: valid_attributes.merge(recipient_email: "  invalid address  ")
          }
        end
      end

      assert_response :unprocessable_entity
      assert_equal "Admin/Store/GiftCards/Form", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_equal "  invalid address  ", props.dig(:gift_card, :recipient_email)
      assert props.dig(:form_errors, :recipient_email).present?
    end

    test "update ignores recipient delivery fields and never treats them as model attributes" do
      card = Commerce::GiftCard.create!(
        code: "GC#{SecureRandom.alphanumeric(12).upcase}",
        balance_cents: 2_500,
        initial_balance_cents: 2_500,
        currency: "CNY",
        active: true,
        created_by: @staff
      )

      MailDeliveryJob.stub(:perform_later, ->(*) { flunk("updates must not send creation mail") }) do
        patch admin_store_gift_card_path(card), params: {
          gift_card: {
            balance_cents: 2_500,
            currency: "CNY",
            active: true,
            note: "Updated without email delivery",
            recipient_email: "attacker@example.com"
          }
        }
      end

      assert_redirected_to admin_store_gift_card_path(card)
      assert_equal "Updated without email delivery", card.reload.note
    end

    private

    def valid_attributes
      {
        code: "GC#{SecureRandom.alphanumeric(12).upcase}",
        balance_cents: 2_500,
        currency: "USD",
        expires_at: 1.year.from_now.strftime("%Y-%m-%dT%H:%M"),
        note: "Welcome gift",
        active: true
      }
    end
  end
end
