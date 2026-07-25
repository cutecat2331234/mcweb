# frozen_string_literal: true

require "test_helper"

class ActionViewTemplateResolutionTest < ActiveSupport::TestCase
  test "uses the Windows compatibility resolver only when absolute globbing is broken" do
    views_root = Rails.root.join("app", "views")
    relative_matches = Dir.glob("layouts/application*", base: views_root.to_s)
    absolute_matches = Dir.glob(views_root.join("layouts", "application*").to_s)

    assert_includes relative_matches, "layouts/application.html.erb"

    if absolute_matches.empty?
      assert Gem.win_platform?
      assert_includes ActionView::FileSystemResolver.ancestors, Mcweb::WindowsActionViewGlobCompat
    else
      assert_includes absolute_matches, views_root.join("layouts", "application.html.erb").to_s
    end
  end

  test "resolves controller layouts from the application view path" do
    lookup = ActionView::LookupContext.new(ApplicationController._view_paths)

    assert lookup.exists?("layouts/inertia", [], false, [], formats: [ :html ])
  end

  test "resolves namespaced mailer templates from the application view path" do
    lookup = ActionView::LookupContext.new(Commerce::OrderMailer._view_paths)

    assert lookup.exists?("order_created", [ "commerce/order_mailer" ], false, [], formats: [ :html ])
  end
end
