# frozen_string_literal: true

require "test_helper"

module Community
  class AttachmentMediaInspectorTest < ActiveSupport::TestCase
    Upload = Struct.new(:tempfile, :content_type)

    test "accepts PNG JPG and JPEG only after pixel decoding and returns sanitized bytes" do
      png = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::WHITE)
      png.metadata["Comment"] = "private screenshot metadata"
      jpeg = Vips::Image.black(3, 2).new_from_image([ 30, 120, 220 ])
        .jpegsave_buffer(Q: 94, strip: true, interlace: false)

      [
        [ "screenshot.PNG", "image/png", png.to_blob ],
        [ "screenshot.jpg", "image/jpeg", jpeg ],
        [ "screenshot.jpeg", "image/jpeg", jpeg ]
      ].each do |filename, content_type, payload|
        io = Upload.new(StringIO.new(payload), content_type)
        io.tempfile.pos = 4
        result = inspect_attachment(filename, io)

        assert_predicate result, :success?, filename
        assert_equal content_type, result.content_type
        assert_equal result.payload.bytesize, result.byte_size
        assert_predicate result.payload, :frozen?
        assert_equal 4, io.tempfile.pos
        refute_equal payload, result.payload
        refute_includes result.payload, "private screenshot metadata"
      end
    end

    test "rejects conflicting image MIME missing MIME and disguised extensions" do
      png = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::WHITE).to_blob
      jpeg = Vips::Image.black(2, 2).jpegsave_buffer(strip: true, interlace: false)
      [
        [ "screenshot.png", "text/html", png ],
        [ "screenshot.png", "application/octet-stream", png ],
        [ "screenshot.png", nil, png ],
        [ "screenshot.png", "image/jpeg", png ],
        [ "screenshot.jpg", "image/jpeg", png ],
        [ "screenshot.jpeg", "image/jpeg", png ],
        [ "screenshot.png", "image/png", jpeg ],
        [ "screenshot.png", "image/png", "<svg><script/></svg>" ],
        [ "screenshot.jpeg", "image/jpeg", "MZ executable" ],
        [ "screenshot.log", "image/png", png ]
      ].each do |filename, content_type, payload|
        result = inspect_attachment(filename, Upload.new(StringIO.new(payload), content_type))

        refute_predicate result, :success?, "#{filename} / #{content_type.inspect}"
      end
    end

    test "still allows internal image streams to be reinspected without a request MIME" do
      png = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::WHITE).to_blob

      result = inspect_attachment("screenshot.png", StringIO.new(png))

      assert_predicate result, :success?
      assert_equal "image/png", result.content_type
    end

    test "uses both subject and site allowlists without enabling uninspected video" do
      png = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::WHITE).to_blob
      io = Upload.new(StringIO.new(png), "image/png")

      refute_predicate AllowedAttachmentTypes.inspect_file(
        filename: "screenshot.png", io:, allowed_extensions: %w[log]
      ), :success?

      SiteSetting.set("forum.attachments.allowed_extensions", "log")
      refute_predicate inspect_attachment("screenshot.png", io), :success?

      SiteSetting.set("forum.attachments.allowed_extensions", "mp4,webm,svg,gif")
      %w[mp4 webm svg gif].each do |extension|
        refute_predicate AllowedAttachmentTypes.inspect_file(
          filename: "unsupported.#{extension}",
          io: StringIO.new("uninspected media"),
          allowed_extensions: [ extension ]
        ), :success?
      end
    end

    test "accepts safe UTF logs with browser empty or generic MIME and normalizes the stored encoding" do
      text = "[12:30:00] 玩家 joined\n[12:30:01] action=complete\r\n"
      payloads = [
        text.b,
        "\xEF\xBB\xBF".b + text.b,
        "\xFF\xFE".b + text.encode(Encoding::UTF_16LE).b,
        "\xFE\xFF".b + text.encode(Encoding::UTF_16BE).b
      ]

      [ nil, "", "application/octet-stream", "text/plain", "text/plain; charset=utf-8" ].each do |mime|
        payloads.each do |payload|
          io = Upload.new(StringIO.new(payload), mime)
          io.tempfile.pos = 2
          result = inspect_attachment("server.log", io)

          assert_predicate result, :success?, mime.inspect
          assert_equal "text/plain", result.content_type
          assert_equal text.b, result.payload
          assert_equal text.bytesize, result.byte_size
          assert_equal 2, io.tempfile.pos
        end
      end
    end

    test "rejects binary invalid encoding control bytes executable and markup disguised as logs" do
      [
        "MZ executable".b,
        "\x7FELF".b,
        "PK\x03\x04".b,
        "log\x00binary".b,
        "log\x1B[31mcontrol".b,
        "log\xFF".b,
        "\xFF\xFEa".b,
        "#!/bin/sh\nrm anything",
        "<html><script>alert(1)</script></html>",
        "\xFF\xFE".b + "MZ executable".encode(Encoding::UTF_16LE).b,
        "\xFF\xFE".b + "log\x00binary".encode(Encoding::UTF_16LE).b
      ].each do |payload|
        result = inspect_attachment("server.log", Upload.new(StringIO.new(payload), "application/octet-stream"))

        refute_predicate result, :success?
      end

      %w[image/png video/mp4 text/html application/json].each do |mime|
        result = inspect_attachment("server.log", Upload.new(StringIO.new("plain log"), mime))

        refute_predicate result, :success?, mime
      end
    end

    test "enforces both original and normalized byte limits for logs" do
      oversized = inspect_attachment("server.log", StringIO.new("x" * 6), max_bytes: 5)
      text = "日志" * 10
      encoded = "\xFF\xFE".b + text.encode(Encoding::UTF_16LE).b
      assert_operator encoded.bytesize, :<, 50
      normalized_oversized = inspect_attachment("server.log", StringIO.new(encoded), max_bytes: 50)

      assert_predicate oversized, :too_large?
      assert_predicate normalized_oversized, :too_large?
      assert_equal text.bytesize, normalized_oversized.byte_size
    end

    private

    def inspect_attachment(filename, io, max_bytes: 1.megabyte)
      AllowedAttachmentTypes.inspect_file(
        filename:,
        io:,
        allowed_extensions: %w[png jpg jpeg log],
        max_bytes:
      )
    end
  end
end
