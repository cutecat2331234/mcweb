# frozen_string_literal: true

# Ruby 4.0.6 on Windows can return no matches for an absolute Dir.glob pattern
# even though the same directory is readable and a base-relative glob works.
# Action View's filesystem resolver uses absolute glob patterns internally, so
# the bug otherwise makes every controller layout and mailer template appear to
# be missing.
module Mcweb
  module WindowsActionViewGlobCompat
    private

    def template_glob(glob)
      root = path.to_s
      path_with_slash = File.join(root, "")

      Dir.glob(glob, base: root).filter_map do |relative_path|
        filename = File.expand_path(relative_path, root)
        next if File.directory?(filename)
        next unless filename.start_with?(path_with_slash)

        filename
      end
    end
  end
end

views_root = Rails.root.join("app", "views")
absolute_probe = views_root.join("layouts", "application*").to_s
relative_probe = File.join("layouts", "application*")

if Gem.win_platform? &&
   Dir.glob(absolute_probe).empty? &&
   Dir.glob(relative_probe, base: views_root.to_s).any?
  require "action_view/template/resolver"
  ActionView::FileSystemResolver.prepend(Mcweb::WindowsActionViewGlobCompat)
end
