# frozen_string_literal: true

module Commerce
  class GenerateOrderReceiptPdf < ApplicationService
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
      pdf.text "Status: #{@order.status}"
      pdf.move_down 16
      pdf.text "Items", style: :bold
      pdf.move_down 8

      @order.items.each do |item|
        pdf.text "- #{item.product_name} x#{item.quantity}  #{format_money(item.total_cents, @order.currency)}"
      end

      pdf.move_down 16
      pdf.text "Total: #{format_money(@order.total_cents, @order.currency)}", style: :bold

      ServiceResult.success(pdf.render)
    rescue LoadError
      ServiceResult.failure(error: "PDF generation is not available.")
    end

    private

    def format_money(cents, currency)
      amount = cents / 100.0
      "#{currency} #{format('%.2f', amount)}"
    end
  end
end
