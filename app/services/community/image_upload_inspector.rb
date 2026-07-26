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

          frame_seen = true
        elsif marker == 0xDA
          return false if scan_seen || !frame_seen

          scan_seen = true
          entropy_coded = true
        end
        offset = segment_end
      end

      false
    end
    private_class_method :single_complete_jpeg_stream?

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
