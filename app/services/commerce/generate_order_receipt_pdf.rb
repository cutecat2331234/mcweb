# frozen_string_literal: true

module Commerce
  class GenerateOrderReceiptPdf < ApplicationService
    STATUS_LABELS = {
      "pending" => "Pending",
      "awaiting_payment" => "Awaiting payment",
      "paid" => "Paid",
      "processing" => "Processing",
      "fulfilling" => "Fulfilling",
      "fulfilled" => "Fulfilled",
      "completed" => "Completed",
      "cancelled" => "Cancelled",
      "refunded" => "Refunded",
      "failed" => "Failed"
    }.freeze

    def initialize(order:)
      @order = order
    end

    def call
      require "prawn"

      pdf = Prawn::Document.new(page_size: "A4", margin: 48)
      pdf.font "Helvetica"
      pdf.text "Order Receipt", size: 20, style: :bold
      pdf.move_down 12
      pdf.text "Order: #{@order.order_number}"
      pdf.text "Date: #{@order.created_at.strftime('%Y-%m-%d %H:%M')}"
      pdf.text "Status: #{order_status_label(@order.status)}"
      pdf.text "Customer notes: #{ascii_safe(@order.notes)}" if @order.notes.present?
      if @order.shipping_address.present? && @order.shipping_address.values.any?(&:present?)
        pdf.text "Shipping address: #{ascii_safe(format_address(@order.shipping_address))}"
      end
      if @order.shipping_method.present?
        pdf.text "Shipping method: #{ascii_safe(Commerce::ShippingMethods.label_for(@order.shipping_method))}"
      end
      if @order.tracking_number.present?
        pdf.text "Tracking: #{ascii_safe(@order.shipping_carrier)} #{@order.tracking_number}"
      end
      pdf.move_down 16
      pdf.text "Items", style: :bold
      pdf.move_down 8

      @order.items.each do |item|
        name = ascii_safe(item.product_name)
        variant = item.variant_name.present? ? " (#{ascii_safe(item.variant_name)})" : ""
        pdf.text "- #{name}#{variant} x#{item.quantity}  #{format_money(item.total_cents, @order.currency)}"
      end

      pdf.move_down 8
      pdf.text "Subtotal: #{format_money(@order.subtotal_cents, @order.currency)}"
      if @order.discount_cents.positive?
        code = @order.coupon&.code
        pdf.text "Discount#{code ? " (#{code})" : ""}: -#{format_money(@order.discount_cents, @order.currency)}"
      end
      if @order.gift_card_amount_cents.positive?
        code = @order.gift_card&.code
        pdf.text "Gift card#{code ? " (#{code})" : ""}: -#{format_money(@order.gift_card_amount_cents, @order.currency)}"
      end
      if @order.shipping_cents.positive?
        pdf.text "Shipping: #{format_money(@order.shipping_cents, @order.currency)}"
      elsif @order.subtotal_cents.positive?
        pdf.text "Shipping: Free"
      end
      if @order.gift_wrap_cents.positive?
        pdf.text "Gift wrap: #{format_money(@order.gift_wrap_cents, @order.currency)}"
      end

      pdf.move_down 8
      pdf.text "Total: #{format_money(@order.total_cents, @order.currency)}", style: :bold

      ServiceResult.success(pdf.render)
    rescue LoadError
      ServiceResult.failure(error: "PDF generation is not available.")
    end

    private

    def order_status_label(status)
      STATUS_LABELS[status.to_s] || status.to_s
    end

    def ascii_safe(text)
      text.to_s.encode("ASCII", invalid: :replace, undef: :replace, replace: "?")
    end

    def format_money(cents, currency)
      amount = cents / 100.0
      "#{currency} #{format('%.2f', amount)}"
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
