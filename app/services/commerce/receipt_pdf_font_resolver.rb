# frozen_string_literal: true

module Commerce
  class ReceiptPdfFontResolver
    class FontUnavailable < StandardError; end

    FontSet = Struct.new(:normal, :bold, :normal_index, :bold_index, keyword_init: true) do
      def normal_definition
        font_definition(normal, normal_index)
      end

      def bold_definition
        font_definition(bold, bold_index)
      end

      private

      def font_definition(path, index)
        index.nil? ? path : { file: path, font: index }
      end
    end

    DEFAULT_FONT_SETS = [
      {
        normal: "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        bold: "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
        normal_index: 2,
        bold_index: 2
      },
      {
        normal: "C:/Windows/Fonts/msyh.ttc",
        bold: "C:/Windows/Fonts/msyhbd.ttc"
      },
      {
        normal: "C:/Windows/Fonts/simsun.ttc",
        bold: "C:/Windows/Fonts/simhei.ttf"
      },
      {
        normal: "/System/Library/Fonts/PingFang.ttc",
        bold: "/System/Library/Fonts/PingFang.ttc"
      }
    ].freeze

    def resolve!
      configured_normal = ENV["MCWEB_RECEIPT_FONT_PATH"].presence
      configured_bold = ENV["MCWEB_RECEIPT_FONT_BOLD_PATH"].presence

      if configured_normal.present? || configured_bold.present?
        return configured_font_set!(configured_normal, configured_bold)
      end

      pair = DEFAULT_FONT_SETS.find do |candidate|
        File.file?(candidate.fetch(:normal)) && File.file?(candidate.fetch(:bold))
      end
      raise FontUnavailable, "No supported Unicode receipt font was found" unless pair

      FontSet.new(**pair)
    end

    private

    def configured_font_set!(normal, bold)
      raise FontUnavailable, "MCWEB_RECEIPT_FONT_PATH is required when a receipt font override is configured" if normal.blank?

      bold = normal if bold.blank?
      unless File.file?(normal) && File.file?(bold)
        raise FontUnavailable, "The configured Unicode receipt font file does not exist"
      end

      FontSet.new(normal: File.expand_path(normal), bold: File.expand_path(bold))
    end
  end
end
