# frozen_string_literal: true

require "test_helper"
require "mcweb/image_pack_registry"

class Mcweb::ImagePackRegistryTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir
    @config_path = Pathname(@tmpdir).join("image_packs.yml")
    @example_path = Pathname(@tmpdir).join("image_packs.yml.example")
    @textures = Pathname(@tmpdir).join("textures", "item")
    @textures.mkpath
    @textures.join("diamond.png").write("png")

    @example_path.write(<<~YAML)
      packs:
        demo:
          label: Demo Pack
          namespace: demo
          root: #{@textures.dirname.to_s.gsub("\\", "/")}
    YAML

    @original_config = ENV["MCWEB_IMAGE_PACKS_PATH"]
    @original_example = ENV["MCWEB_IMAGE_PACKS_EXAMPLE_PATH"]
    ENV["MCWEB_IMAGE_PACKS_PATH"] = @config_path.to_s
    ENV["MCWEB_IMAGE_PACKS_EXAMPLE_PATH"] = @example_path.to_s
    Mcweb::ImagePackRegistry.reload!
  end

  teardown do
    if @original_config
      ENV["MCWEB_IMAGE_PACKS_PATH"] = @original_config
    else
      ENV.delete("MCWEB_IMAGE_PACKS_PATH")
    end
    if @original_example
      ENV["MCWEB_IMAGE_PACKS_EXAMPLE_PATH"] = @original_example
    else
      ENV.delete("MCWEB_IMAGE_PACKS_EXAMPLE_PATH")
    end
    Mcweb::ImagePackRegistry.reload!
    Pathname(@tmpdir).rmtree if @tmpdir && Pathname(@tmpdir).exist?
  end

  test "ensure_config! copies example without raising when config missing" do
    assert_not @config_path.exist?

    path = Mcweb::ImagePackRegistry.ensure_config!
    assert_equal @config_path, path
    assert @config_path.exist?
  end

  test "find returns pack metadata" do
    Mcweb::ImagePackRegistry.ensure_config!
    pack = Mcweb::ImagePackRegistry.find("demo")

    assert_not_nil pack
    assert_equal "Demo Pack", pack["label"]
    assert_equal "demo", pack["namespace"]
  end

  test "texture_path resolves png under pack root" do
    Mcweb::ImagePackRegistry.ensure_config!

    path = Mcweb::ImagePackRegistry.texture_path("demo", "item", "diamond")
    assert_equal @textures.join("diamond.png").to_s, path
  end

  test "texture_path returns nil for missing files" do
    Mcweb::ImagePackRegistry.ensure_config!

    assert_nil Mcweb::ImagePackRegistry.texture_path("demo", "item", "missing")
  end

  test "frontend_hash reports availability" do
    Mcweb::ImagePackRegistry.ensure_config!

    hash = Mcweb::ImagePackRegistry.frontend_hash
    assert_equal true, hash.dig("demo", "available")
  end
end
