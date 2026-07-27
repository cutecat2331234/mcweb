# frozen_string_literal: true

require "chunky_png"
require "stringio"
require "vips"

module Community
  module ImageUploadInspector
    READ_CHUNK_BYTES = 64.kilobytes
    MAX_DIMENSION = 8_192
    MAX_PIXELS = 8_000_000
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
    JPEG_START = "\xFF\xD8".b
    JPEG_END = "\xFF\xD9".b
    JPEG_QUALITY = 85
    JPEG_ALLOWED_BANDS = [ 1, 3, 4 ].freeze
    JPEG_FRAME_MARKERS = [
      0xC0, 0xC1, 0xC2, 0xC3,
      0xC5, 0xC6, 0xC7,
      0xC9, 0xCA, 0xCB,
      0xCD, 0xCE, 0xCF
    ].freeze
    JPEG_BASELINE_FRAME_MARKER = 0xC0
    JPEG_HUFFMAN_TABLE_MARKER = 0xC4
    JPEG_QUANTIZATION_TABLE_MARKER = 0xDB
    JPEG_MAX_HUFFMAN_TABLE_ID = 1
    JPEG_MAX_QUANTIZATION_TABLE_ID = 3
    JPEG_PROCESSING_MUTEX = Mutex.new

    Result = Struct.new(
      :status,
      :content_type,
      :extension,
      :width,
      :height,
      :payload,
      keyword_init: true
    ) do
      def success?
        status == :ok
      end

      def too_large?
        status == :too_large
      end
    end

    module_function

    def call(io:, max_bytes:)
      payload = read_bounded(io, max_bytes)
      return result(:too_large) if payload.bytesize > max_bytes
      return result(:unsupported) if payload.empty?

      inspected = if payload.start_with?(PNG_SIGNATURE)
        inspect_png(payload)
      elsif payload.start_with?(JPEG_START)
        inspect_jpeg(payload)
      else
        result(:unsupported)
      end
      return result(:too_large) if inspected.success? && inspected.payload.bytesize > max_bytes

      inspected
    rescue StandardError
      result(:unreadable)
    end

    def inspect_png(payload)
      width, height = png_dimensions(payload)
      return result(:unsupported) unless dimensions_allowed?(width, height)

      image = ChunkyPNG::Image.from_blob(payload)
      return result(:unsupported) unless image.width == width && image.height == height

      result(
        :ok,
        content_type: "image/png",
        extension: "png",
        width: width,
        height: height,
        payload: image.to_blob.freeze
      )
    end
    private_class_method :inspect_png

    def png_dimensions(payload)
      return [ nil, nil ] unless payload.bytesize >= 33
      return [ nil, nil ] unless payload.byteslice(12, 4) == "IHDR"

      payload.byteslice(16, 8).unpack("NN")
    end
    private_class_method :png_dimensions

    def inspect_jpeg(payload)
      return result(:unsupported) unless single_complete_jpeg_stream?(payload)

      JPEG_PROCESSING_MUTEX.synchronize do
        image = Vips::Image.jpegload_buffer(
          payload,
          access: :sequential,
          fail_on: :warning,
          unlimited: false
        )
        return result(:unsupported) unless dimensions_allowed?(image.width, image.height)
        return result(:unsupported) unless JPEG_ALLOWED_BANDS.include?(image.bands)

        image = image.autorot
        return result(:unsupported) unless dimensions_allowed?(image.width, image.height)

        image = image.colourspace(:srgb) unless image.bands == 1
        sanitized = image.jpegsave_buffer(
          Q: JPEG_QUALITY,
          optimize_coding: false,
          interlace: false,
          strip: true
        )
        return result(:unsupported) unless single_complete_jpeg_stream?(sanitized)

        result(
          :ok,
          content_type: "image/jpeg",
          extension: "jpg",
          width: image.width,
          height: image.height,
          payload: sanitized.freeze
        )
      end
    rescue Vips::Error
      result(:unsupported)
    end
    private_class_method :inspect_jpeg

    def single_complete_jpeg_stream?(payload)
      return false unless payload.start_with?(JPEG_START)

      offset = JPEG_START.bytesize
      entropy_coded = false
      frame_seen = false
      scan_seen = false
      frame_components = nil
      quantization_tables = {}
      huffman_tables = {}

      while offset < payload.bytesize
        if entropy_coded
          marker_start = payload.index("\xFF".b, offset)
          return false unless marker_start

          marker_offset = marker_start + 1
          marker_offset += 1 while payload.getbyte(marker_offset) == 0xFF
          marker = payload.getbyte(marker_offset)
          return false unless marker

          case marker
          when 0x00, 0xD0..0xD7
            offset = marker_offset + 1
          when 0xD9
            return frame_seen && scan_seen && marker_offset + 1 == payload.bytesize
          when 0xD8
            return false
          else
            entropy_coded = false
            offset = marker_start
          end
          next
        end

        return false unless payload.getbyte(offset) == 0xFF

        marker_offset = offset + 1
        marker_offset += 1 while payload.getbyte(marker_offset) == 0xFF
        marker = payload.getbyte(marker_offset)
        return false unless marker

        case marker
        when 0xD9
          return frame_seen && scan_seen && marker_offset + 1 == payload.bytesize
        when 0x00, 0x01, 0xD0..0xD8
          return false
        end

        length_offset = marker_offset + 1
        segment_length = payload.byteslice(length_offset, 2)&.unpack1("n")
        return false unless segment_length&.>= 2

        segment_end = length_offset + segment_length
        return false if segment_end > payload.bytesize

        if JPEG_FRAME_MARKERS.include?(marker)
          return false if frame_seen || marker != JPEG_BASELINE_FRAME_MARKER

          frame_components = parse_baseline_frame_segment(
            payload,
            length_offset + 2,
            segment_end
          )
          return false unless frame_components

          frame_seen = true
        elsif marker == JPEG_QUANTIZATION_TABLE_MARKER
          return false unless parse_quantization_tables(
            payload,
            length_offset + 2,
            segment_end,
            quantization_tables
          )
        elsif marker == JPEG_HUFFMAN_TABLE_MARKER
          return false unless parse_huffman_tables(
            payload,
            length_offset + 2,
            segment_end,
            huffman_tables
          )
        elsif marker == 0xDA
          return false if scan_seen || !frame_seen
          return false unless valid_baseline_scan_segment?(
            payload,
            length_offset + 2,
            segment_end,
            frame_components,
            quantization_tables,
            huffman_tables
          )

          scan_seen = true
          entropy_coded = true
        end
        offset = segment_end
      end

      false
    end
    private_class_method :single_complete_jpeg_stream?

    def parse_baseline_frame_segment(payload, data_offset, segment_end)
      component_count = payload.getbyte(data_offset + 5)
      return nil unless component_count&.between?(1, 4)
      return nil unless segment_end - data_offset == 6 + (component_count * 3)
      return nil unless payload.getbyte(data_offset) == 8

      height = payload.byteslice(data_offset + 1, 2)&.unpack1("n")
      width = payload.byteslice(data_offset + 3, 2)&.unpack1("n")
      return nil unless dimensions_allowed?(width, height)

      components = {}
      cursor = data_offset + 6
      component_count.times do
        component_id = payload.getbyte(cursor)
        sampling_factors = payload.getbyte(cursor + 1)
        quantization_table_id = payload.getbyte(cursor + 2)
        return nil unless component_id && sampling_factors && quantization_table_id
        return nil if components.key?(component_id)
        return nil unless valid_sampling_factors?(sampling_factors)
        return nil unless quantization_table_id.between?(0, JPEG_MAX_QUANTIZATION_TABLE_ID)

        components[component_id] = quantization_table_id
        cursor += 3
      end
      components
    end
    private_class_method :parse_baseline_frame_segment

    def valid_sampling_factors?(value)
      horizontal = value >> 4
      vertical = value & 0x0F
      horizontal.between?(1, 4) && vertical.between?(1, 4)
    end
    private_class_method :valid_sampling_factors?

    def parse_quantization_tables(payload, data_offset, segment_end, tables)
      cursor = data_offset
      while cursor < segment_end
        descriptor = payload.getbyte(cursor)
        return false unless descriptor

        precision = descriptor >> 4
        table_id = descriptor & 0x0F
        return false unless precision.zero?
        return false unless table_id.between?(0, JPEG_MAX_QUANTIZATION_TABLE_ID)

        cursor += 1
        table_bytes = 64 * (precision + 1)
        return false if cursor + table_bytes > segment_end

        tables[table_id] = true
        cursor += table_bytes
      end
      cursor == segment_end
    end
    private_class_method :parse_quantization_tables

    def parse_huffman_tables(payload, data_offset, segment_end, tables)
      cursor = data_offset
      while cursor < segment_end
        descriptor = payload.getbyte(cursor)
        return false unless descriptor

        table_class = descriptor >> 4
        table_id = descriptor & 0x0F
        return false unless table_class.between?(0, 1)
        return false unless table_id.between?(0, JPEG_MAX_HUFFMAN_TABLE_ID)

        code_counts = payload.byteslice(cursor + 1, 16)
        return false unless code_counts&.bytesize == 16

        symbol_count = code_counts.bytes.sum
        return false unless symbol_count.between?(1, 256)

        cursor += 17
        return false if cursor + symbol_count > segment_end

        tables[[ table_class, table_id ]] = true
        cursor += symbol_count
      end
      cursor == segment_end
    end
    private_class_method :parse_huffman_tables

    def valid_baseline_scan_segment?(
      payload,
      data_offset,
      segment_end,
      frame_components,
      quantization_tables,
      huffman_tables
    )
      scan_component_count = payload.getbyte(data_offset)
      return false unless scan_component_count == frame_components.size
      return false unless segment_end - data_offset == 4 + (scan_component_count * 2)
      return false unless frame_components.values.all? { |table_id| quantization_tables.key?(table_id) }

      cursor = data_offset + 1
      scan_component_ids = []
      scan_component_count.times do
        component_id = payload.getbyte(cursor)
        table_selectors = payload.getbyte(cursor + 1)
        return false unless component_id && table_selectors
        return false unless frame_components.key?(component_id)
        return false if scan_component_ids.include?(component_id)

        dc_table_id = table_selectors >> 4
        ac_table_id = table_selectors & 0x0F
        return false unless dc_table_id.between?(0, JPEG_MAX_HUFFMAN_TABLE_ID)
        return false unless ac_table_id.between?(0, JPEG_MAX_HUFFMAN_TABLE_ID)
        return false unless huffman_tables.key?([ 0, dc_table_id ])
        return false unless huffman_tables.key?([ 1, ac_table_id ])

        scan_component_ids << component_id
        cursor += 2
      end

      payload.byteslice(cursor, 3)&.bytes == [ 0, 63, 0 ]
    end
    private_class_method :valid_baseline_scan_segment?

    def dimensions_allowed?(width, height)
      width.to_i.positive? &&
        height.to_i.positive? &&
        width <= MAX_DIMENSION &&
        height <= MAX_DIMENSION &&
        width * height <= MAX_PIXELS
    end
    private_class_method :dimensions_allowed?

    def read_bounded(io, max_bytes)
      source_io = io.respond_to?(:tempfile) ? io.tempfile : io
      raise ArgumentError, "image IO is required" unless source_io.respond_to?(:read)
      raise ArgumentError, "image size limit must be positive" unless max_bytes.to_i.positive?

      original_position = source_io.pos if source_io.respond_to?(:pos)
      source_io.rewind
      payload = +"".b

      while payload.bytesize <= max_bytes
        remaining = (max_bytes + 1) - payload.bytesize
        break unless remaining.positive?

        chunk = source_io.read([ READ_CHUNK_BYTES, remaining ].min)
        break if chunk.nil? || chunk.empty?

        payload << chunk.b
      end

      payload
    ensure
      if defined?(source_io) && source_io
        if defined?(original_position) && !original_position.nil? && source_io.respond_to?(:seek)
          source_io.seek(original_position, IO::SEEK_SET)
        elsif source_io.respond_to?(:rewind)
          source_io.rewind
        end
      end
    end
    private_class_method :read_bounded

    def result(status, **attributes)
      Result.new(status: status, **attributes)
    end
    private_class_method :result
  end
end
