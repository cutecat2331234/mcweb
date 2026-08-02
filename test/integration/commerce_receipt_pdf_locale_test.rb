# frozen_string_literal: true

require "test_helper"

class CommerceReceiptPdfLocaleTest < ActionDispatch::IntegrationTest
  test "legacy unsupported user locale does not break receipt download" do
    user = create_user(locale: "en")
    order = Commerce::Order.create!(
      public_id: "order_#{SecureRandom.alphanumeric(16)}",
      user: user,
      order_number: "LEGACY-LOCALE",
      status: "paid",
      subtotal_cents: 1_000,
      discount_cents: 0,
      total_cents: 1_000,
      currency: "CNY"
    )
    sign_in_as(user)
    user.update_column(:locale, "legacy-invalid")

    Commerce::GenerateOrderReceiptPdf.stub(:call, ServiceResult.success("%PDF-1.4\n")) do
      get receipt_pdf_store_order_path(order)
    end

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_includes response.headers.fetch("Content-Disposition"), "LEGACY-LOCALE"
  end
end
