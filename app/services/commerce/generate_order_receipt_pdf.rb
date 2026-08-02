# frozen_string_literal: true

module Commerce
  class GenerateOrderReceiptPdf < ApplicationService
    FONT_FAMILY = "McWebReceiptUnicode"

    def initialize(order:, font_resolver: Commerce::ReceiptPdfFontResolver.new)
      @order = order
      @font_resolver = font_resolver
    end

    def call
      require "prawn"

      I18n.with_locale(recipient_locale) do
        font_set = @font_resolver.resolve!
        pdf = Prawn::Document.new(page_size: "A4", margin: 48)
        register_unicode_font!(pdf, font_set)
        render_receipt(pdf)
        ServiceResult.success(pdf.render)
      end
    rescue Commerce::ReceiptPdfFontResolver::FontUnavailable => e
      Rails.logger.error("PDF receipt Unicode font unavailable: #{e.message}")
      I18n.with_locale(recipient_locale) do
        ServiceResult.failure(
          error: :pdf_unicode_font_is_not_available,
          code: "pdf_unicode_font_unavailable"
        )
      end
    rescue LoadError
      I18n.with_locale(recipient_locale) do
        ServiceResult.failure(error: :pdf_generation_is_not_available, code: "pdf_generation_unavailable")
      end
    end

    private

    def recipient_locale
      Mcweb::LocaleResolver.resolve(@order.user&.locale)
    end

    def register_unicode_font!(pdf, font_set)
      pdf.font_families.update(
        FONT_FAMILY => {
          normal: font_set.normal_definition,
          bold: font_set.bold_definition
        }
      )
      pdf.font(FONT_FAMILY)
    rescue StandardError => e
      raise Commerce::ReceiptPdfFontResolver::FontUnavailable, e.message
    end

    def render_receipt(pdf)
      pdf.text receipt_t(:title), size: 20, style: :bold
      pdf.move_down 12
      pdf.text receipt_t(:order_number, number: @order.order_number)
      pdf.text receipt_t(:date, date: I18n.l(@order.created_at, format: :long))
      pdf.text receipt_t(:status, status: order_status_label(@order.status))
      pdf.text receipt_t(:notes, notes: unicode_safe(@order.notes)) if @order.notes.present?

      if @order.shipping_address.present? && @order.shipping_address.values.any?(&:present?)
        pdf.text receipt_t(:shipping_address, address: unicode_safe(format_address(@order.shipping_address)))
      end
      if @order.shipping_method.present?
        method = Commerce::ShippingMethods.label_for(@order.shipping_method)
        pdf.text receipt_t(:shipping_method, method: unicode_safe(method))
      end
      if @order.tracking_number.present?
        pdf.text receipt_t(
          :tracking,
          carrier: unicode_safe(@order.shipping_carrier),
          number: unicode_safe(@order.tracking_number)
        )
      end

      pdf.move_down 16
      pdf.text receipt_t(:items), style: :bold
      pdf.move_down 8

      @order.items.each do |item|
        variant = item.variant_name.present? ? " (#{unicode_safe(item.variant_name)})" : ""
        pdf.text receipt_t(
          :item,
          name: unicode_safe(item.product_name),
          variant: variant,
          quantity: item.quantity,
          amount: format_money(item.total_cents, @order.currency)
        )
      end

      pdf.move_down 8
      pdf.text receipt_t(:subtotal, amount: format_money(@order.subtotal_cents, @order.currency))
      if @order.discount_cents.positive?
        code = @order.coupon&.code
        pdf.text receipt_t(
          :discount,
          code: code ? " (#{unicode_safe(code)})" : "",
          amount: format_money(@order.discount_cents, @order.currency)
        )
      end
      if @order.gift_card_amount_cents.positive?
        code = @order.gift_card&.code
        pdf.text receipt_t(
          :gift_card,
          code: code ? " (#{unicode_safe(code)})" : "",
          amount: format_money(@order.gift_card_amount_cents, @order.currency)
        )
      end
      if @order.shipping_cents.positive?
        pdf.text receipt_t(:shipping, amount: format_money(@order.shipping_cents, @order.currency))
      elsif @order.subtotal_cents.positive?
        pdf.text receipt_t(:free_shipping)
      end
      if @order.gift_wrap_cents.positive?
        pdf.text receipt_t(:gift_wrap, amount: format_money(@order.gift_wrap_cents, @order.currency))
      end

      pdf.move_down 8
      pdf.text receipt_t(:total, amount: format_money(@order.total_cents, @order.currency)), style: :bold
      pdf.move_down 16
      pdf.text receipt_t(:footer), size: 9
    end

    def receipt_t(key, **options)
      I18n.t("mcweb.mail.commerce.receipt.#{key}", **options)
    end

    def order_status_label(status)
      I18n.t("mcweb.labels.order_status.#{status}", default: status.to_s)
    end

    def unicode_safe(text)
      text.to_s
        .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�")
        .unicode_normalize(:nfc)
        .gsub(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/, "")
    end

    def format_money(cents, currency)
      amount = cents / 100.0
      "#{unicode_safe(currency)} #{format('%.2f', amount)}"
    end

    def format_address(address)
      return "" unless address.is_a?(Hash)

      [
        address["name"],
        address["phone"],
        [ address["province"], address["city"] ].compact.join(" "),
        [ address["line1"], address["line2"] ].compact.join(" "),
        address["postal_code"]
      ].map(&:presence).compact.join(", ")
    end
  end
end
