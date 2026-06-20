# frozen_string_literal: true

module Admin
  module Store
    class GiftCardsController < BaseController
      before_action -> { require_permission("store.products.manage") }

      def index
        cards = ::Commerce::GiftCard.order(created_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.store.gift_cards.title"),
          columns: [
            admin_column(:code, t("mcweb.admin.store.gift_cards.col_code"), link: true),
            admin_column(:balance, t("mcweb.admin.store.gift_cards.col_balance")),
            admin_column(:active, t("mcweb.admin.store.gift_cards.col_status"))
          ],
          rows: cards.map do |card|
            admin_row(
              code: card.code,
              balance: format_money(card.balance_cents, card.currency),
              active: gift_card_status_label(card.active?),
              url: admin_store_gift_card_path(card)
            )
          end,
          actions: [ { label: t("mcweb.admin.store.gift_cards.new"), href: new_admin_store_gift_card_path } ]
        }
      end

      def show
        card = ::Commerce::GiftCard.includes(:transactions, :orders).find(params[:id])
        orders = card.orders.order(created_at: :desc).limit(10)
        render inertia: "Admin/Generic/Show", props: {
          title: card.code,
          fields: [
            { label: t("mcweb.admin.store.gift_cards.field_balance"), value: format_money(card.balance_cents, card.currency) },
            { label: t("mcweb.admin.store.gift_cards.field_initial_balance"), value: format_money(card.initial_balance_cents, card.currency) },
            { label: t("mcweb.admin.store.gift_cards.field_status"), value: gift_card_status_label(card.active?) },
            { label: t("mcweb.admin.store.gift_cards.field_expires_at"), value: card.expires_at ? l(card.expires_at, format: :short) : t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.gift_cards.field_note"), value: card.note.presence || t("mcweb.labels.not_available") }
          ],
          sections: [
            {
              title: t("mcweb.admin.store.gift_cards.section_usage"),
              items: orders.map do |order|
                { label: order.order_number, value: "#{format_money(order.gift_card_amount_cents, order.currency)} · #{order_status_label(order.status)}" }
              end.presence || [ { label: t("mcweb.admin.store.gift_cards.record_label"), value: t("mcweb.admin.store.gift_cards.empty_records") } ]
            },
            {
              title: t("mcweb.admin.store.gift_cards.section_transactions"),
              items: card.transactions.order(created_at: :desc).limit(15).map do |tx|
                sign = tx.amount_cents.positive? ? "+" : ""
                {
                  label: l(tx.created_at, format: :short),
                  value: t(
                    "mcweb.admin.store.gift_cards.transaction_line",
                    sign: sign,
                    amount: format_money(tx.amount_cents.abs, card.currency),
                    balance: format_money(tx.balance_after_cents, card.currency)
                  )
                }
              end.presence || [ { label: t("mcweb.admin.store.gift_cards.record_label"), value: t("mcweb.admin.store.gift_cards.empty_records") } ]
            }
          ],
          backUrl: admin_store_gift_cards_path,
          actions: [
            { label: t("mcweb.admin.store.action_edit"), href: edit_admin_store_gift_card_path(card) }
          ]
        }
      end

      def edit
        card = ::Commerce::GiftCard.find(params[:id])
        render inertia: "Admin/Store/GiftCards/Form", props: form_props(card, editing: true)
      end

      def update
        card = ::Commerce::GiftCard.find(params[:id])
        if card.update(gift_card_params)
          redirect_to admin_store_gift_card_path(card), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.gift_card"))
        else
          render inertia: "Admin/Store/GiftCards/Form", props: form_props(card, editing: true), status: :unprocessable_entity
        end
      end

      def new
        render inertia: "Admin/Store/GiftCards/Form", props: form_props(::Commerce::GiftCard.new)
      end

      def create
        card = ::Commerce::GiftCard.new(gift_card_params)
        card.created_by = current_user
        card.initial_balance_cents = card.balance_cents if card.initial_balance_cents.to_i.zero?
        card.code = generate_code if card.code.blank?

        if card.save
          if params[:gift_card][:recipient_email].present?
            MailDeliveryJob.perform_later(
              "Commerce::GiftCardMailer",
              "gift_card_created",
              "deliver_now",
              args: [ card.id, params[:gift_card][:recipient_email] ]
            )
          end
          redirect_to admin_store_gift_card_path(card), notice: t("mcweb.flash.created", resource: t("mcweb.resources.gift_card"))
        else
          render inertia: "Admin/Store/GiftCards/Form", props: form_props(card), status: :unprocessable_entity
        end
      end

      private

      def gift_card_params
        params.require(:gift_card).permit(:code, :balance_cents, :currency, :expires_at, :note, :active, :recipient_email)
      end

      def form_props(card, editing: false)
        {
          title: editing ? t("mcweb.admin.store.gift_cards.edit") : t("mcweb.admin.store.gift_cards.new"),
          gift_card: {
            code: card.code || "",
            balance_cents: card.balance_cents || 0,
            currency: card.currency || "CNY",
            expires_at: card.expires_at&.strftime("%Y-%m-%dT%H:%M"),
            note: card.note || "",
            active: card.active != false,
            recipient_email: ""
          },
          submitUrl: editing ? admin_store_gift_card_path(card) : admin_store_gift_cards_path,
          method: editing ? "patch" : "post",
          backUrl: editing ? admin_store_gift_card_path(card) : admin_store_gift_cards_path
        }
      end

      def generate_code
        loop do
          code = "GC#{SecureRandom.alphanumeric(12).upcase}"
          break code unless ::Commerce::GiftCard.exists?(code: code)
        end
      end
    end
  end
end
