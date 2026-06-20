# frozen_string_literal: true

require "test_helper"
require "mcweb/image_pack_registry"

class Commerce::ResolveProductImageUrlTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir
    @textures = Pathname(@tmpdir).join("textures", "item")
    @textures.mkpath
    @textures.join("japariman.png").write("png")

    @config_path = Pathname(@tmpdir).join("image_packs.yml")
    @config_path.write(<<~YAML)
      packs:
        demo:
          label: Demo
          namespace: demo
          root: #{@textures.dirname.to_s.gsub("\\", "/")}
    YAML

    @original = ENV["MCWEB_IMAGE_PACKS_PATH"]
    ENV["MCWEB_IMAGE_PACKS_PATH"] = @config_path.to_s
    Mcweb::ImagePackRegistry.reload!
  end

  teardown do
    if @original
      ENV["MCWEB_IMAGE_PACKS_PATH"] = @original
    else
      ENV.delete("MCWEB_IMAGE_PACKS_PATH")
    end
    Mcweb::ImagePackRegistry.reload!
    Pathname(@tmpdir).rmtree if @tmpdir && Pathname(@tmpdir).exist?
  end

  test "returns image pack texture url when configured in fulfillment_config" do
    product = Commerce::Product.new(
      fulfillment_config: {
        "image_pack" => "demo",
        "image_texture" => "item/japariman"
      }
    )

    url = Commerce::ResolveProductImageUrl.call(product: product).value[:url]
    assert_includes url, "/app/store/image-packs/demo/item/japariman"
  end

  test "falls back to external image_url when pack texture missing" do
    product = Commerce::Product.new(
      image_url: "https://cdn.example.com/item.png",
      fulfillment_config: { "image_pack" => "demo", "image_texture" => "item/missing" }
    )

    url = Commerce::ResolveProductImageUrl.call(product: product).value[:url]
    assert_equal "https://cdn.example.com/item.png", url
  end
end

class Commerce::ImagePackTexturesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmpdir = Dir.mktmpdir
    @textures = Pathname(@tmpdir).join("textures", "item")
    @textures.mkpath
    @textures.join("diamond.png").write("png")

    @config_path = Pathname(@tmpdir).join("image_packs.yml")
    @config_path.write(<<~YAML)
      packs:
        demo:
          label: Demo
          namespace: demo
          root: #{@textures.dirname.to_s.gsub("\\", "/")}
    YAML

    @original = ENV["MCWEB_IMAGE_PACKS_PATH"]
    ENV["MCWEB_IMAGE_PACKS_PATH"] = @config_path.to_s
    Mcweb::ImagePackRegistry.reload!
  end

  teardown do
    if @original
      ENV["MCWEB_IMAGE_PACKS_PATH"] = @original
    else
      ENV.delete("MCWEB_IMAGE_PACKS_PATH")
    end
    Mcweb::ImagePackRegistry.reload!
    Pathname(@tmpdir).rmtree if @tmpdir && Pathname(@tmpdir).exist?
  end

  test "serves texture file for valid pack path" do
    get store_image_pack_texture_path(pack_id: "demo", texture_path: "item/diamond")
    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "returns not found for path traversal" do
    get "/app/store/image-packs/demo/item/..%2F..%2Fetc/passwd"
    assert_response :not_found
  end

  test "returns not found for missing texture" do
    get store_image_pack_texture_path(pack_id: "demo", texture_path: "item/missing")
    assert_response :not_found
  end
end
