# frozen_string_literal: true

require "test_helper"
require "prawn"

class Commerce::ReceiptPdfI18nTest < ActiveSupport::TestCase
  class CapturingPdf
    attr_reader :texts, :font_families

    def initialize
      @texts = []
      @font_families = {}
    end

    def font(*) = nil
    def move_down(*) = nil
    def text(value, **) = texts << value
    def render = "%PDF-captured"
  end

  class StaticFontResolver
    def resolve!
      Commerce::ReceiptPdfFontResolver::FontSet.new(normal: "normal.ttf", bold: "bold.ttf")
    end
  end

  setup do
    @user = create_user(locale: "zh-CN")
    @order = Commerce::Order.create!(
      public_id: "order_#{SecureRandom.alphanumeric(16)}",
      user: @user,
      order_number: "PDF-ZH-1",
      status: "paid",
      subtotal_cents: 1_288,
      discount_cents: 0,
      shipping_cents: 0,
      total_cents: 1_288,
      currency: "CNY",
      notes: "请放在门卫室",
      shipping_address: {
        "name" => "张三",
        "province" => "北京市",
        "city" => "海淀区",
        "line1" => "中关村大街一号"
      }
    )
    Commerce::OrderItem.create!(
      order: @order,
      product_name: "中文限定商品",
      variant_name: "红色款",
      quantity: 1,
      unit_price_cents: 1_288,
      total_cents: 1_288
    )
  end

  test "Chinese product address and notes reach Prawn unchanged instead of question marks" do
    pdf = CapturingPdf.new

    Prawn::Document.stub(:new, ->(*) { pdf }) do
      result = Commerce::GenerateOrderReceiptPdf.call(order: @order, font_resolver: StaticFontResolver.new)
      assert_predicate result, :success?
    end

    rendered_text = pdf.texts.join("\n")
    assert_includes rendered_text, "订单收据"
    assert_includes rendered_text, "中文限定商品"
    assert_includes rendered_text, "红色款"
    assert_includes rendered_text, "北京市 海淀区"
    assert_includes rendered_text, "中关村大街一号"
    assert_includes rendered_text, "请放在门卫室"
    refute_includes rendered_text, "?"
  end

  test "receipt copy follows the order user locale" do
    @user.update!(locale: "en")
    pdf = CapturingPdf.new

    Prawn::Document.stub(:new, ->(*) { pdf }) do
      Commerce::GenerateOrderReceiptPdf.call(order: @order, font_resolver: StaticFontResolver.new)
    end

    assert_equal "Order receipt", pdf.texts.first
    assert_includes pdf.texts, "Status: Paid"
  end

  test "missing configured font returns an explicit functional failure" do
    resolver = Object.new
    resolver.define_singleton_method(:resolve!) do
      raise Commerce::ReceiptPdfFontResolver::FontUnavailable, "missing font"
    end

    result = Commerce::GenerateOrderReceiptPdf.call(order: @order, font_resolver: resolver)

    assert_predicate result, :failure?
    assert_equal "pdf_unicode_font_unavailable", result.code
    assert_includes result.error, "Unicode 字体"
  end

  test "font resolver rejects missing configured files" do
    resolver = Commerce::ReceiptPdfFontResolver.new

    assert_raises(Commerce::ReceiptPdfFontResolver::FontUnavailable) do
      resolver.send(:configured_font_set!, "Z:/missing/receipt-font.ttf", nil)
    end
  end

  test "Linux Noto CJK definitions select the Simplified Chinese TTC face" do
    linux = Commerce::ReceiptPdfFontResolver::DEFAULT_FONT_SETS.first
    font_set = Commerce::ReceiptPdfFontResolver::FontSet.new(**linux)

    assert_equal 2, font_set.normal_index
    assert_equal 2, font_set.bold_index
    assert_equal({ file: linux.fetch(:normal), font: 2 }, font_set.normal_definition)
    assert_equal({ file: linux.fetch(:bold), font: 2 }, font_set.bold_definition)
  end

  test "installed Unicode font renders Chinese through real Prawn" do
    resolver = Commerce::ReceiptPdfFontResolver.new
    begin
      font_set = resolver.resolve!
    rescue Commerce::ReceiptPdfFontResolver::FontUnavailable => error
      skip "No supported local Unicode font: #{error.message}"
    end

    assert File.file?(font_set.normal)
    assert File.file?(font_set.bold)

    result = Commerce::GenerateOrderReceiptPdf.call(order: @order, font_resolver: resolver)

    assert_predicate result, :success?
    assert result.value.b.start_with?("%PDF".b)
    assert_operator result.value.bytesize, :>, 1_000
  end

  test "long receipts create additional real PDF pages" do
    resolver = Commerce::ReceiptPdfFontResolver.new
    begin
      resolver.resolve!
    rescue Commerce::ReceiptPdfFontResolver::FontUnavailable => error
      skip "No supported local Unicode font: #{error.message}"
    end

    120.times do |index|
      Commerce::OrderItem.create!(
        order: @order,
        product_name: "分页商品 #{index + 1}",
        variant_name: "规格 #{index + 1}",
        quantity: 1,
        unit_price_cents: 100,
        total_cents: 100
      )
    end

    result = Commerce::GenerateOrderReceiptPdf.call(order: @order, font_resolver: resolver)

    assert_predicate result, :success?
    assert_operator result.value.scan(%r{/Type\s*/Page\b}).size, :>, 1
  end

  test "Linux Noto CJK font paths resolve and render when installed" do
    skip "Linux-only production font contract" unless RUBY_PLATFORM.include?("linux")

    normal = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
    bold = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
    assert File.file?(normal), "missing required Linux receipt font: #{normal}"
    assert File.file?(bold), "missing required Linux receipt font: #{bold}"

    resolver = Commerce::ReceiptPdfFontResolver.new
    font_set = resolver.resolve!
    assert_equal normal, font_set.normal
    assert_equal bold, font_set.bold
    assert_equal 2, font_set.normal_index
    assert_equal 2, font_set.bold_index

    result = Commerce::GenerateOrderReceiptPdf.call(order: @order, font_resolver: resolver)
    assert_predicate result, :success?
    assert result.value.b.start_with?("%PDF".b)
  end
end
