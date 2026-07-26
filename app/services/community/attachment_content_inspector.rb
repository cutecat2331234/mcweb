# frozen_string_literal: true

require "csv"
require "json"
require "stringio"
require "zip"
require "zlib"

module Community
  module AttachmentContentInspector
    READ_CHUNK_BYTES = 64.kilobytes
    MAX_ZIP_ENTRIES = 10_000
    MAX_ZIP_UNCOMPRESSED_BYTES = 128.megabytes
    MAX_ZIP_COMPRESSION_RATIO = 200
    MAX_OFFICE_XML_BYTES = 2.megabytes
    MAX_RAR_HEADER_BYTES = 2.megabytes

    ZIP_SIGNATURES = [
      "PK\x03\x04".b,
      "PK\x05\x06".b
    ].freeze
    SEVEN_Z_SIGNATURE = "7z\xBC\xAF\x27\x1C".b
    RAR4_SIGNATURE = "Rar!\x1A\x07\x00".b
    RAR5_SIGNATURE = "Rar!\x1A\x07\x01\x00".b
    COMPOUND_FILE_SIGNATURE = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b

    COMPOUND_FREE_SECTOR = 0xFFFFFFFF
    COMPOUND_END_OF_CHAIN = 0xFFFFFFFE

    OPENXML_FORMATS = {
      "docx" => {
        payload: "word/document.xml",
        content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
        root: /<(?:[A-Za-z0-9_]+:)?document\b/
      },
      "xlsx" => {
        payload: "xl/workbook.xml",
        content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
        root: /<(?:[A-Za-z0-9_]+:)?workbook\b/
      },
      "pptx" => {
        payload: "ppt/presentation.xml",
        content_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml",
        root: /<(?:[A-Za-z0-9_]+:)?presentation\b/
      }
    }.freeze

    LEGACY_OFFICE_STREAMS = {
      "doc" => [ "WordDocument" ],
      "xls" => [ "Workbook", "Book" ],
      "ppt" => [ "PowerPoint Document" ]
    }.freeze

    EXECUTABLE_SIGNATURES = [
      "MZ".b,
      "\x7FELF".b,
      "\xCA\xFE\xBA\xBE".b,
      "\x00asm".b,
      "\xFE\xED\xFA\xCE".b,
      "\xFE\xED\xFA\xCF".b,
      "\xCE\xFA\xED\xFE".b,
      "\xCF\xFA\xED\xFE".b
    ].freeze

    Result = Struct.new(:status, :content_type, :byte_size, :payload, keyword_init: true) do
      def success?
        status == :ok
      end

      def too_large?
        status == :too_large
      end
    end

    module_function

    def call(extension:, io:, max_bytes:, content_type:)
      payload = read_bounded(io, max_bytes)
      return result(:too_large, byte_size: payload.bytesize) if payload.bytesize > max_bytes
      return result(:unsupported, byte_size: payload.bytesize) if payload.empty?
      return result(:unsupported, byte_size: payload.bytesize) if executable_payload?(payload)
      return result(:unsupported, byte_size: payload.bytesize) unless valid_for_extension?(extension, payload)

      result(
        :ok,
        content_type: content_type,
        byte_size: payload.bytesize,
        payload: payload.freeze
      )
    rescue StandardError
      result(:unreadable)
    end

    def read_bounded(io, max_bytes)
      source_io = io.respond_to?(:tempfile) ? io.tempfile : io
      raise ArgumentError, "attachment IO is required" unless source_io.respond_to?(:read)
      raise ArgumentError, "attachment size limit must be positive" unless max_bytes.to_i.positive?

      original_position = source_io.pos if source_io.respond_to?(:pos)
      source_io.rewind
      payload = +"".b

      while payload.bytesize <= max_bytes
        remaining = (max_bytes + 1) - payload.bytesize
        break if remaining <= 0

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

    def valid_for_extension?(extension, payload)
      case extension
      when "txt", "md"
        valid_plain_text?(payload)
      when "json"
        valid_json?(payload)
      when "csv"
        valid_csv?(payload)
      when "pdf"
        valid_pdf?(payload)
      when "zip", "docx", "xlsx", "pptx"
        valid_zip_format?(payload, extension)
      when "doc", "xls", "ppt"
        valid_compound_office?(payload, extension)
      when "7z"
        valid_seven_zip?(payload)
      when "rar"
        valid_rar?(payload)
      else
        false
      end
    end
    private_class_method :valid_for_extension?

    def executable_payload?(payload)
      EXECUTABLE_SIGNATURES.any? { |signature| payload.start_with?(signature) } ||
        payload.start_with?("#!".b)
    end
    private_class_method :executable_payload?

    def valid_plain_text?(payload)
      text = decoded_text(payload)
      text.present? && !dangerous_markup?(text)
    end
    private_class_method :valid_plain_text?

    def valid_json?(payload)
      text = decoded_text(payload)
      return false unless text

      JSON.parse(text, max_nesting: 100)
      true
    rescue JSON::ParserError
      false
    end
    private_class_method :valid_json?

    def valid_csv?(payload)
      text = decoded_text(payload)
      return false unless text
      return false if dangerous_markup?(text)

      CSV.parse(text, liberal_parsing: false)
      true
    rescue CSV::MalformedCSVError
      false
    end
    private_class_method :valid_csv?

    def decoded_text(payload)
      text = if payload.start_with?("\xEF\xBB\xBF".b)
        payload.byteslice(3..).dup.force_encoding(Encoding::UTF_8)
      elsif payload.start_with?("\xFF\xFE".b)
        payload.byteslice(2..).dup.force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
      elsif payload.start_with?("\xFE\xFF".b)
        payload.byteslice(2..).dup.force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8)
      else
        payload.dup.force_encoding(Encoding::UTF_8)
      end
      return nil unless text.valid_encoding?
      return nil if text.match?(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/)

      text
    rescue EncodingError
      nil
    end
    private_class_method :decoded_text

    def dangerous_markup?(text)
      candidate = text.lstrip
      4.times do
        if candidate.start_with?("<!--")
          comment_end = candidate.index("-->")
          break unless comment_end

          candidate = candidate.byteslice((comment_end + 3)..).to_s.lstrip
          next
        end

        if candidate.match?(/\A<\?xml\b/i)
          declaration_end = candidate.index("?>")
          break unless declaration_end

          candidate = candidate.byteslice((declaration_end + 2)..).to_s.lstrip
          next
        end

        break
      end

      candidate.match?(
        /\A(?:<!doctype\s+(?:html|svg)\b|<(?:html|head|body|script|svg|iframe|object|embed|link|meta|style|form|input|button|video|audio|canvas|math|h[1-6]|div|span|p|a|table)\b)/i
      )
    end
    private_class_method :dangerous_markup?

    def valid_pdf?(payload)
      return false unless payload.match?(/\A%PDF-(?:1\.[0-7]|2\.0)[\r\n]/)
      return false unless payload.include?(" obj".b) || payload.match?(/[\r\n]\d+\s+\d+\s+obj\b/)
      return false unless payload.include?("/Root".b)

      trailer = payload.match(/startxref\s+(\d+)\s+%%EOF\s*\z/m)
      return false unless trailer

      xref_offset = trailer[1].to_i
      return false if xref_offset >= payload.bytesize

      payload.byteslice(xref_offset, 64).to_s.match?(/\A(?:xref\b|\d+\s+\d+\s+obj\b)/)
    end
    private_class_method :valid_pdf?

    def valid_zip_format?(payload, extension)
      return false unless ZIP_SIGNATURES.any? { |signature| payload.start_with?(signature) }

      Zip::File.open_buffer(StringIO.new(payload)) do |archive|
        return false unless valid_zip_metadata?(archive)
        return false unless decodable_zip_entries?(archive)
        return true if extension == "zip"

        valid_openxml_office?(archive, extension)
      end
    rescue Zip::Error, SystemCallError
      false
    end
    private_class_method :valid_zip_format?

    def valid_zip_metadata?(archive)
      return false if archive.entries.length > MAX_ZIP_ENTRIES

      seen = {}
      total_size = 0

      archive.entries.all? do |entry|
        name = normalized_zip_name(entry.name)
        next false unless name
        next false if seen.key?(name.downcase)
        next false if entry.respond_to?(:symlink?) && entry.symlink?

        seen[name.downcase] = true
        size = entry.size.to_i
        compressed_size = entry.compressed_size.to_i
        total_size += size
        next false if total_size > MAX_ZIP_UNCOMPRESSED_BYTES
        next false if compressed_size.zero? && size.positive?
        next false if compressed_size.positive? && (size.to_f / compressed_size) > MAX_ZIP_COMPRESSION_RATIO

        true
      end
    end
    private_class_method :valid_zip_metadata?

    def decodable_zip_entries?(archive)
      total_bytes = 0

      archive.entries.all? do |entry|
        next true if entry.directory?

        entry_bytes = 0
        crc = Zlib.crc32
        entry.get_input_stream do |input|
          loop do
            chunk = input.read(READ_CHUNK_BYTES)
            break if chunk.nil? || chunk.empty?

            entry_bytes += chunk.bytesize
            total_bytes += chunk.bytesize
            return false if total_bytes > MAX_ZIP_UNCOMPRESSED_BYTES

            crc = Zlib.crc32(chunk, crc)
          end
        end

        entry_bytes == entry.size.to_i && crc == entry.crc.to_i
      end
    rescue Zip::Error, Zlib::Error
      false
    end
    private_class_method :decodable_zip_entries?

    def normalized_zip_name(raw_name)
      name = raw_name.to_s.dup
      name.force_encoding(Encoding::UTF_8)
      return nil unless name.valid_encoding?
      return nil if name.empty? || name.bytesize > 4_096
      return nil if name.include?("\0") || name.include?("\\")
      return nil if name.start_with?("/") || name.match?(/\A[A-Za-z]:/)

      name = name.delete_suffix("/")
      parts = name.split("/")
      return nil if parts.empty? || parts.any? { |part| part.empty? || part == "." || part == ".." }

      name
    end
    private_class_method :normalized_zip_name

    def valid_openxml_office?(archive, extension)
      format = OPENXML_FORMATS.fetch(extension)
      entries = archive.entries.index_by(&:name)
      required_names = [ "[Content_Types].xml", "_rels/.rels", format.fetch(:payload) ]
      return false unless required_names.all? { |name| entries.key?(name) }
      return false if entries.keys.any? { |name| macro_office_entry?(name) }

      content_types = read_small_zip_entry(entries.fetch("[Content_Types].xml"))
      relationships = read_small_zip_entry(entries.fetch("_rels/.rels"))
      payload = read_small_zip_entry(entries.fetch(format.fetch(:payload)))
      return false unless content_types && relationships && payload

      content_types_text = decoded_text(content_types)
      relationships_text = decoded_text(relationships)
      payload_text = decoded_text(payload)
      return false unless safe_xml?(content_types_text) && safe_xml?(relationships_text) && safe_xml?(payload_text)
      return false if content_types_text.match?(/macroEnabled|vbaProject/i)
      return false unless content_types_text.include?(format.fetch(:content_type))
      return false unless content_types_text.match?(/<(?:[A-Za-z0-9_]+:)?Types\b/)
      return false unless relationships_text.match?(/<(?:[A-Za-z0-9_]+:)?Relationships\b/)

      payload_text.match?(format.fetch(:root))
    end
    private_class_method :valid_openxml_office?

    def macro_office_entry?(name)
      normalized = name.to_s.downcase
      normalized.end_with?("vbaproject.bin") || normalized.include?("/macros/")
    end
    private_class_method :macro_office_entry?

    def read_small_zip_entry(entry)
      return nil if entry.size.to_i > MAX_OFFICE_XML_BYTES

      entry.get_input_stream do |input|
        data = input.read(MAX_OFFICE_XML_BYTES + 1).to_s.b
        return nil if data.bytesize > MAX_OFFICE_XML_BYTES
        return nil unless data.bytesize == entry.size.to_i

        data
      end
    rescue Zip::Error, Zlib::Error
      nil
    end
    private_class_method :read_small_zip_entry

    def safe_xml?(text)
      text.present? && !text.match?(/<!DOCTYPE|<!ENTITY/i)
    end
    private_class_method :safe_xml?

    def valid_compound_office?(payload, extension)
      return false unless payload.start_with?(COMPOUND_FILE_SIGNATURE)
      return false if payload.bytesize < 1_024

      major_version = uint16(payload, 26)
      sector_shift = uint16(payload, 30)
      return false unless [ [ 3, 9 ], [ 4, 12 ] ].include?([ major_version, sector_shift ])
      return false unless payload.byteslice(28, 2) == "\xFE\xFF".b
      return false unless uint16(payload, 32) == 6

      sector_size = 1 << sector_shift
      return false unless (payload.bytesize % sector_size).zero?

      sector_count = (payload.bytesize / sector_size) - 1
      fat_sector_count = uint32(payload, 44)
      return false unless fat_sector_count.positive? && fat_sector_count <= 109

      fat_sector_ids = payload.byteslice(76, 109 * 4).unpack("V*")
        .reject { |sector_id| sector_id == COMPOUND_FREE_SECTOR }
        .first(fat_sector_count)
      return false unless fat_sector_ids.length == fat_sector_count
      return false unless fat_sector_ids.uniq.length == fat_sector_ids.length
      return false unless fat_sector_ids.all? { |sector_id| sector_id < sector_count }

      fat = fat_sector_ids.flat_map do |sector_id|
        compound_sector(payload, sector_id, sector_size)&.unpack("V*")
      end
      return false if fat.any?(&:nil?)

      directory = compound_chain(
        payload,
        first_sector: uint32(payload, 48),
        sector_size: sector_size,
        sector_count: sector_count,
        fat: fat
      )
      return false unless directory

      names = compound_directory_names(directory)
      expected_streams = LEGACY_OFFICE_STREAMS.fetch(extension)
      names.include?("Root Entry") && expected_streams.any? { |name| names.include?(name) }
    rescue ArgumentError, EncodingError
      false
    end
    private_class_method :valid_compound_office?

    def compound_chain(payload, first_sector:, sector_size:, sector_count:, fat:)
      return nil if first_sector >= sector_count

      data = +"".b
      seen = {}
      sector_id = first_sector

      while sector_id != COMPOUND_END_OF_CHAIN
        return nil if sector_id >= sector_count || seen.key?(sector_id)

        seen[sector_id] = true
        sector = compound_sector(payload, sector_id, sector_size)
        return nil unless sector

        data << sector
        sector_id = fat[sector_id]
        return nil if sector_id.nil? || sector_id == COMPOUND_FREE_SECTOR
      end

      data
    end
    private_class_method :compound_chain

    def compound_sector(payload, sector_id, sector_size)
      offset = (sector_id + 1) * sector_size
      payload.byteslice(offset, sector_size) if offset + sector_size <= payload.bytesize
    end
    private_class_method :compound_sector

    def compound_directory_names(directory)
      names = []

      0.step(directory.bytesize - 128, 128) do |offset|
        entry = directory.byteslice(offset, 128)
        object_type = entry.getbyte(66)
        next if object_type == 0
        return [] unless [ 1, 2, 5 ].include?(object_type)

        name_length = uint16(entry, 64)
        return [] unless name_length.even? && name_length.between?(2, 64)

        raw_name = entry.byteslice(0, name_length - 2)
        name = raw_name.force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
        names << name
      end

      names
    end
    private_class_method :compound_directory_names

    def valid_seven_zip?(payload)
      return false unless payload.start_with?(SEVEN_Z_SIGNATURE)
      return false if payload.bytesize < 32
      return false unless payload.getbyte(6).zero?

      start_header = payload.byteslice(12, 20)
      return false unless Zlib.crc32(start_header) == uint32(payload, 8)

      next_header_offset = payload.byteslice(12, 8).unpack1("Q<")
      next_header_size = payload.byteslice(20, 8).unpack1("Q<")
      return false unless next_header_size.positive?

      next_header_start = 32 + next_header_offset
      next_header_end = next_header_start + next_header_size
      return false if next_header_start < 32 || next_header_end > payload.bytesize

      Zlib.crc32(payload.byteslice(next_header_start, next_header_size)) == uint32(payload, 28)
    end
    private_class_method :valid_seven_zip?

    def valid_rar?(payload)
      if payload.start_with?(RAR4_SIGNATURE)
        valid_rar4_archive?(payload)
      elsif payload.start_with?(RAR5_SIGNATURE)
        valid_rar5_archive?(payload)
      else
        false
      end
    end
    private_class_method :valid_rar?

    def valid_rar4_archive?(payload)
      offset = RAR4_SIGNATURE.bytesize
      first_header = true
      end_header_seen = false

      while offset < payload.bytesize
        return false if payload.bytesize - offset < 7

        header_type = payload.getbyte(offset + 2)
        header_flags = uint16(payload, offset + 3)
        header_size = uint16(payload, offset + 5)
        return false unless header_type.between?(0x72, 0x7B)
        return false if first_header && header_type != 0x73
        return false if header_size < 7 || offset + header_size > payload.bytesize

        stored_crc = uint16(payload, offset)
        calculated_crc = Zlib.crc32(payload.byteslice(offset + 2, header_size - 2)) & 0xFFFF
        return false unless stored_crc == calculated_crc

        data_size = 0
        if (header_flags & 0x8000).positive?
          return false if header_size < 11

          data_size = uint32(payload, offset + 7)
        end
        if header_type == 0x74 && (header_flags & 0x0100).positive?
          return false if header_size < 40
          return false unless uint32(payload, offset + 32).zero?
        end

        next_offset = offset + header_size + data_size
        return false if next_offset > payload.bytesize

        offset = next_offset
        first_header = false
        if header_type == 0x7B
          end_header_seen = true
          break
        end
      end

      end_header_seen && offset == payload.bytesize
    end
    private_class_method :valid_rar4_archive?

    def valid_rar5_archive?(payload)
      offset = RAR5_SIGNATURE.bytesize
      first_header = true
      end_header_seen = false

      while offset < payload.bytesize
        return false if payload.bytesize - offset < 7

        stored_crc = uint32(payload, offset)
        header_size, header_start = read_vint(payload, offset + 4)
        return false unless header_size&.positive? && header_size <= MAX_RAR_HEADER_BYTES

        header_end = header_start + header_size
        return false if header_end > payload.bytesize
        calculated_crc = Zlib.crc32(payload.byteslice(offset + 4, header_end - (offset + 4)))
        return false unless calculated_crc == stored_crc

        header_type, cursor = read_vint(payload, header_start)
        header_flags, cursor = read_vint(payload, cursor)
        return false unless header_type&.between?(1, 5) && header_flags
        return false if first_header && header_type != 1

        if (header_flags & 0x0001).positive?
          extra_size, cursor = read_vint(payload, cursor)
          return false unless extra_size
        end

        data_size = 0
        if (header_flags & 0x0002).positive?
          data_size, cursor = read_vint(payload, cursor)
          return false unless data_size
        end
        return false if cursor > header_end

        next_offset = header_end + data_size
        return false if next_offset > payload.bytesize

        offset = next_offset
        first_header = false
        if header_type == 5
          end_header_seen = true
          break
        end
      end

      end_header_seen && offset == payload.bytesize
    end
    private_class_method :valid_rar5_archive?

    def read_vint(payload, offset)
      value = 0
      shift = 0

      10.times do
        byte = payload.getbyte(offset)
        return [ nil, nil ] unless byte

        offset += 1
        value |= (byte & 0x7F) << shift
        return [ value, offset ] if (byte & 0x80).zero?

        shift += 7
      end

      [ nil, nil ]
    end
    private_class_method :read_vint

    def uint16(payload, offset)
      payload.byteslice(offset, 2).unpack1("v")
    end
    private_class_method :uint16

    def uint32(payload, offset)
      payload.byteslice(offset, 4).unpack1("V")
    end
    private_class_method :uint32

    def result(status, content_type: nil, byte_size: nil, payload: nil)
      Result.new(
        status: status,
        content_type: content_type,
        byte_size: byte_size,
        payload: payload
      )
    end
    private_class_method :result
  end
end
