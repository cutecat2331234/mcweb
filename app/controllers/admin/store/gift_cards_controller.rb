# frozen_string_literal: true

module Admin
  module Store
    class GiftCardsController < BaseController
      before_action -> { require_permission("store.products.manage") }

      def index
        cards = ::Commerce::GiftCard.order(created_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: "礼品卡",
          columns: [
            admin_column(:code, "代码", link: true),
            admin_column(:balance, "余额"),
            admin_column(:active, "状态")
          ],
          rows: cards.map do |card|
            admin_row(
              code: card.code,
              balance: format_money(card.balance_cents, card.currency),
              active: card.active? ? "可用" : "停用",
              url: admin_store_gift_card_path(card)
            )
          end,
          actions: [{ label: "新建礼品卡", href: new_admin_store_gift_card_path }]
        }
      end

      def show
        card = ::Commerce::GiftCard.find(params[:id])
        render inertia: "Admin/Generic/Show", props: {
          title: card.code,
          fields: [
            { label: "余额", value: format_money(card.balance_cents, card.currency) },
            { label: "初始面额", value: format_money(card.initial_balance_cents, card.currency) },
            { label: "状态", value: card.active? ? "可用" : "停用" },
            { label: "过期时间", value: card.expires_at ? l(card.expires_at, format: :short) : "—" },
            { label: "备注", value: card.note.presence || "—" }
          ],
          backUrl: admin_store_gift_cards_path
        }
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
          redirect_to admin_store_gift_card_path(card), notice: "礼品卡已创建。"
        else
          render inertia: "Admin/Store/GiftCards/Form", props: form_props(card), status: :unprocessable_entity
        end
      end

      private

      def gift_card_params
        params.require(:gift_card).permit(:code, :balance_cents, :currency, :expires_at, :note, :active)
      end

      def form_props(card)
        {
          title: "新建礼品卡",
          gift_card: {
            code: card.code || "",
            balance_cents: card.balance_cents || 0,
            currency: card.currency || "CNY",
            expires_at: card.expires_at&.strftime("%Y-%m-%dT%H:%M"),
            note: card.note || "",
            active: card.active != false
          },
          submitUrl: admin_store_gift_cards_path,
          backUrl: admin_store_gift_cards_path
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
