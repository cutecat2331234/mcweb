# frozen_string_literal: true

require "test_helper"

class Frontend::PathContainmentTest < ActiveSupport::TestCase
  test "within_root accepts files inside template directory" do
    root = Pathname(Dir.mktmpdir)
    root.join("styles").mkpath
    file = root.join("styles/theme.css")
    file.write("body{}")

    assert Frontend::PathContainment.within_root?(file, root)
  ensure
    root.rmtree if root&.exist?
  end

  test "within_root rejects sibling directories with shared prefix" do
    root = Pathname(Dir.mktmpdir)
    sibling = Pathname("#{root}-evil")
    sibling.mkpath
    file = sibling.join("theme.css")
    file.write("body{}")

    refute Frontend::PathContainment.within_root?(file, root)
  ensure
    root.rmtree if root&.exist?
    sibling.rmtree if defined?(sibling) && sibling&.exist?
  end
end
