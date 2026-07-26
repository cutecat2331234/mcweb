# frozen_string_literal: true

require "test_helper"

module Community
  class ImageUploadInspectorTest < ActiveSupport::TestCase
    test "fully decodes and re-encodes PNG while restoring the input pointer" do
      original = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color.rgb(30, 120, 220)).to_blob
      io = StringIO.new(original)
      io.pos = 3

      result = Community::ImageUploadInspector.call(io: io, max_bytes: 1.megabyte)

      assert result.success?
      assert_equal "image/png", result.content_type
      assert_equal "png", result.extension
      assert_equal [ 2, 2 ], [ result.width, result.height ]
      assert_equal 3, io.pos
      decoded = ChunkyPNG::Image.from_blob(result.payload)
      assert_equal [ 2, 2 ], [ decoded.width, decoded.height ]
    end

    test "rejects markup, unsupported image containers, and corrupt PNG bytes" do
      [
        "<svg xmlns='http://www.w3.org/2000/svg'><script/></svg>",
        "GIF89a\x01\x00\x01\x00".b,
        "RIFF\x10\x00\x00\x00WEBPVP8 ".b,
        Community::ImageUploadInspector::PNG_SIGNATURE + "corrupt"
      ].each do |payload|
        result = Community::ImageUploadInspector.call(
          io: StringIO.new(payload),
          max_bytes: 1.megabyte
        )
        refute result.success?
      end
    end

    test "rejects an image whose declared dimensions exceed the decompression budget" do
      header = Community::ImageUploadInspector::PNG_SIGNATURE +
        [ 13 ].pack("N") +
        "IHDR" +
        [ Community::ImageUploadInspector::MAX_DIMENSION + 1, 1 ].pack("NN") +
        "\x08\x06\x00\x00\x00".b +
        "\x00\x00\x00\x00".b

      result = Community::ImageUploadInspector.call(
        io: StringIO.new(header),
        max_bytes: 1.megabyte
      )

      refute result.success?
    end

    test "fully decodes and re-encodes JPEG while restoring the input pointer" do
      original = valid_jpeg(width: 3, height: 2)
      io = StringIO.new(original)
      io.pos = 4

      result = Community::ImageUploadInspector.call(
        io: io,
        max_bytes: 1.megabyte
      )

      assert result.success?
      assert_equal "image/jpeg", result.content_type
      assert_equal "jpg", result.extension
      assert_equal [ 3, 2 ], [ result.width, result.height ]
      assert_equal 4, io.pos
      refute_equal original, result.payload

      decoded = Vips::Image.jpegload_buffer(result.payload, fail_on: :warning)
      assert_equal [ 3, 2 ], [ decoded.width, decoded.height ]
      assert_equal 3, decoded.bands
    end

    test "rejects structurally plausible and truncated JPEG data" do
      [
        structural_jpeg,
        valid_jpeg.byteslice(0...-2)
      ].each do |payload|
        result = Community::ImageUploadInspector.call(
          io: StringIO.new(payload),
          max_bytes: 1.megabyte
        )

        refute result.success?
      end
    end

    test "rejects progressive JPEG before synchronous normalization" do
      progressive = valid_jpeg(width: 4, height: 3, interlace: true)

      result = Community::ImageUploadInspector.call(
        io: StringIO.new(progressive),
        max_bytes: 1.megabyte
      )

      assert_includes progressive, "\xFF\xC2".b
      refute result.success?
    end

    test "rejects concatenated images and bytes after the first JPEG" do
      jpeg = valid_jpeg

      [
        jpeg + jpeg,
        jpeg + "<script>alert(1)</script>",
        jpeg + "\x00".b
      ].each do |payload|
        result = Community::ImageUploadInspector.call(
          io: StringIO.new(payload),
          max_bytes: 1.megabyte
        )

        refute result.success?
      end
    end

    test "strips JPEG EXIF and comments without copying their payloads" do
      exif_secret = "SECRET-JPEG-EXIF"
      comment_secret = "SECRET-JPEG-COMMENT"
      jpeg = insert_jpeg_segment(
        valid_jpeg_with_exif(exif_secret),
        marker: 0xFE,
        data: comment_secret
      )

      result = Community::ImageUploadInspector.call(
        io: StringIO.new(jpeg),
        max_bytes: 1.megabyte
      )

      assert result.success?
      assert_includes jpeg, exif_secret
      assert_includes jpeg, comment_secret
      refute_includes result.payload, exif_secret
      refute_includes result.payload, comment_secret
      refute_includes result.payload, "Exif\x00\x00".b
      sanitized = Vips::Image.jpegload_buffer(result.payload, fail_on: :warning)
      sanitized.write_to_memory
      sensitive_fields = sanitized.get_fields.grep(
        /comment|exif|icc|iptc|photoshop|xmp/i
      )
      assert_empty sensitive_fields
    end

    test "rejects JPEG dimensions and pixel counts outside the decode budget" do
      jpeg = valid_jpeg

      [
        replace_jpeg_dimensions(
          jpeg,
          width: Community::ImageUploadInspector::MAX_DIMENSION + 1,
          height: 1
        ),
        replace_jpeg_dimensions(jpeg, width: 4_000, height: 2_001)
      ].each do |payload|
        result = Community::ImageUploadInspector.call(
          io: StringIO.new(payload),
          max_bytes: 1.megabyte
        )

        refute result.success?
      end
    end

    test "rejects a valid highly compressed JPEG above the pixel budget" do
      jpeg = valid_jpeg(width: 4_000, height: 2_001)
      assert_operator jpeg.bytesize, :<, 1.megabyte

      result = Community::ImageUploadInspector.call(
        io: StringIO.new(jpeg),
        max_bytes: 1.megabyte
      )

      refute result.success?
    end

    private

    def valid_jpeg(width: 2, height: 2, interlace: false)
      Vips::Image
        .black(width, height)
        .new_from_image([ 30, 120, 220 ])
        .jpegsave_buffer(Q: 94, strip: true, interlace: interlace)
    end

    def valid_jpeg_with_exif(secret)
      image = Vips::Image
        .black(2, 2)
        .new_from_image([ 30, 120, 220 ])
        .copy
      image.set_type(
        GObject::GSTR_TYPE,
        "exif-ifd0-ImageDescription",
        "#{secret} (ASCII, #{secret.bytesize + 1} components, #{secret.bytesize + 1} bytes)"
      )
      image.jpegsave_buffer(Q: 94)
    end

    def insert_jpeg_segment(jpeg, marker:, data:)
      segment = "\xFF".b + marker.chr.b + [ data.bytesize + 2 ].pack("n") + data.b
      jpeg.byteslice(0, 2) + segment + jpeg.byteslice(2..)
    end

    def replace_jpeg_dimensions(jpeg, width:, height:)
      marker_offset = jpeg.index("\xFF\xC0".b)
      raise "baseline JPEG frame marker is missing" unless marker_offset

      modified = jpeg.dup
      modified[marker_offset + 5, 2] = [ height ].pack("n")
      modified[marker_offset + 7, 2] = [ width ].pack("n")
      modified
    end

    def structural_jpeg
      app1 = "\xFF\xE1".b + [ 8 ].pack("n") + "SECRET"
      frame = "\xFF\xC0".b +
        [ 11 ].pack("n") +
        [ 8, 1, 1, 1, 1, 0x11, 0 ].pack("CnnCCCC")
      scan = "\xFF\xDA".b +
        [ 8 ].pack("n") +
        [ 1, 1, 0, 0, 63, 0 ].pack("CCCCCC") +
        "\x01\x02\xFF\x00\x03".b

      Community::ImageUploadInspector::JPEG_START +
        app1 +
        frame +
        scan +
        Community::ImageUploadInspector::JPEG_END
    end
  end
end

class CommunityImageUploadSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(forum_trust_level_override: 1)
    sign_in_as(@user)
    @tempfiles = []
  end

  teardown do
    @tempfiles.each do |file|
      file.close
      file.unlink
    end
  end

  test "derives image type and a safe filename from inspected bytes" do
    png = ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color::WHITE).to_blob
    upload = uploaded_file(png, filename: "avatar.php", declared_type: "text/html")
    inspection = Community::ImageUploadInspector.call(io: upload, max_bytes: 5.megabytes)
    assert inspection.success?, "fixture must be a valid inspected PNG (#{inspection.status})"
    upload.rewind

    before_count = ActiveStorage::Blob.count
    post forum_uploads_path, params: { file: upload }

    assert_response :success, response.body
    assert_equal before_count + 1, ActiveStorage::Blob.count
    blob = ActiveStorage::Blob.order(:id).last
    assert_equal "image/png", blob.content_type
    assert_equal "avatar.png", blob.filename.to_s
    assert_equal png, blob.download
    assert_includes JSON.parse(response.body).fetch("markdown"), "avatar.png"
  end

  test "rejects HTML disguised as an image without saving a blob" do
    upload = uploaded_file(
      "<html><script>alert(1)</script></html>",
      filename: "photo.png",
      declared_type: "image/png"
    )

    assert_no_difference -> { ActiveStorage::Blob.count } do
      post forum_uploads_path, params: { file: upload }
    end

    assert_response :unprocessable_entity
  end

  private

  def uploaded_file(payload, filename:, declared_type:)
    extension = File.extname(filename).presence || ".bin"
    file = Tempfile.new([ "image-upload", extension ])
    @tempfiles << file
    file.binmode
    file.write(payload)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, declared_type, true, original_filename: filename)
  end
end
