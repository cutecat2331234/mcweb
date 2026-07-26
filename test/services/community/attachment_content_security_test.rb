# frozen_string_literal: true

require "test_helper"
require "zip"

class Community::AttachmentContentSecurityTest < ActiveSupport::TestCase
  setup do
    @user = create_user(forum_trust_level_override: 1)
    @tempfiles = []
    @attachments = []
  end

  teardown do
    @attachments.each do |attachment|
      attachment.file.purge if attachment.persisted? && attachment.file.attached?
    end
    @tempfiles.each do |tempfile|
      tempfile.close
      tempfile.unlink
    rescue Errno::ENOENT
      nil
    end
  end

  test "uses inspected bytes and canonical content type instead of the client MIME" do
    file = uploaded_file("notes.txt", "text/html", "safe attachment")
    file.tempfile.seek(4)

    result = Community::CreatePostAttachment.call(user: @user, file: file)

    assert result.success?
    assert_equal 4, file.tempfile.pos

    attachment = track(result.value)
    assert_equal "text/plain", attachment.content_type
    assert_equal "text/plain", attachment.file.blob.content_type
    assert_equal "safe attachment".bytesize, attachment.byte_size
    assert_equal "safe attachment", attachment.file.download
  end

  test "rejects executable HTML SVG and malformed archive payloads hidden by allowed names and MIME" do
    disguised_payloads = {
      "report.txt" => "MZ\x90\x00".b,
      "readme.md" => "<!doctype html><script>alert(1)</script>",
      "drawing.txt" => "<?xml version=\"1.0\"?><svg xmlns=\"http://www.w3.org/2000/svg\"></svg>",
      "manual.pdf" => "%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n",
      "bundle.zip" => "PK\x03\x04not-a-zip".b,
      "corrupt.zip" => zip_with_corrupt_crc,
      "document.docx" => "PK\x03\x04not-an-office-document".b
    }

    disguised_payloads.each do |filename, payload|
      file = uploaded_file(filename, Community::AllowedAttachmentTypes.download_content_type(filename), payload)
      result = Community::CreatePostAttachment.call(user: @user, file: file)

      refute result.success?, "#{filename} was accepted from a forged extension and MIME"
    end
  end

  test "accepts structurally valid PDF ZIP and OpenXML office documents" do
    cases = {
      "manual.pdf" => valid_pdf,
      "bundle.zip" => zip_bytes("notes.txt" => "hello"),
      "document.docx" => openxml_bytes("docx"),
      "sheet.xlsx" => openxml_bytes("xlsx"),
      "slides.pptx" => openxml_bytes("pptx")
    }

    cases.each do |filename, payload|
      file = uploaded_file(filename, "application/octet-stream", payload)
      result = Community::CreatePostAttachment.call(user: @user, file: file)

      assert result.success?, "#{filename} should pass structural inspection"
      attachment = track(result.value)
      assert_equal Community::AllowedAttachmentTypes.download_content_type(filename), attachment.content_type
      assert_equal payload, attachment.file.download
    end
  end

  test "validates decodable structured text rather than trusting its extension" do
    valid_json = uploaded_file("settings.json", "text/plain", JSON.generate({ enabled: true }))
    invalid_json = uploaded_file("settings.json", "application/json", "{not-json")
    malformed_csv = uploaded_file("records.csv", "text/csv", "\"unterminated")

    accepted = Community::CreatePostAttachment.call(user: @user, file: valid_json)
    assert accepted.success?
    track(accepted.value)

    refute Community::CreatePostAttachment.call(user: @user, file: invalid_json).success?
    refute Community::CreatePostAttachment.call(user: @user, file: malformed_csv).success?
  end

  test "bounded inspection stops after the limit and restores the input position" do
    io = StringIO.new("abcdef")
    io.pos = 3

    result = Community::AttachmentContentInspector.call(
      extension: "txt",
      io: io,
      max_bytes: 4,
      content_type: "text/plain"
    )

    assert result.too_large?
    assert_equal 5, result.byte_size
    assert_equal 3, io.pos
  end

  test "conservatively rejects configured extensions without a reliable inspector" do
    io = StringIO.new("otherwise harmless")

    result = Community::AttachmentContentInspector.call(
      extension: "custom",
      io: io,
      max_bytes: 1.megabyte,
      content_type: "application/octet-stream"
    )

    refute result.success?
    assert_equal :unsupported, result.status
  end

  private

  def track(attachment)
    @attachments << attachment
    attachment
  end

  def uploaded_file(name, content_type, content)
    tempfile = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    tempfile.binmode
    tempfile.write(content)
    tempfile.rewind
    @tempfiles << tempfile

    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: name,
      type: content_type
    )
  end

  def valid_pdf
    <<~PDF.b
      %PDF-1.4
      1 0 obj
      << /Type /Catalog >>
      endobj
      trailer
      << /Root 1 0 R >>
      startxref
      9
      %%EOF
    PDF
  end

  def zip_bytes(entries)
    Zip::OutputStream.write_buffer do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end.string
  end

  def zip_with_corrupt_crc
    payload = zip_bytes("notes.txt" => "hello").dup
    central_directory = payload.index("PK\x01\x02".b)
    original_crc = payload.byteslice(central_directory + 16, 4).unpack1("V")
    payload[central_directory + 16, 4] = [ original_crc ^ 0xFFFFFFFF ].pack("V")
    payload
  end

  def openxml_bytes(extension)
    format = {
      "docx" => {
        payload: "word/document.xml",
        content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
        document: '<w:document xmlns:w="urn:word"><w:body /></w:document>'
      },
      "xlsx" => {
        payload: "xl/workbook.xml",
        content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
        document: '<workbook xmlns="urn:sheet"><sheets /></workbook>'
      },
      "pptx" => {
        payload: "ppt/presentation.xml",
        content_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml",
        document: '<p:presentation xmlns:p="urn:presentation"><p:sldIdLst /></p:presentation>'
      }
    }.fetch(extension)

    zip_bytes(
      "[Content_Types].xml" => <<~XML,
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Override PartName="/#{format.fetch(:payload)}" ContentType="#{format.fetch(:content_type)}" />
        </Types>
      XML
      "_rels/.rels" => <<~XML,
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>
      XML
      format.fetch(:payload) => format.fetch(:document)
    )
  end
end
