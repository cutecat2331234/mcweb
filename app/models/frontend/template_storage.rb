# frozen_string_literal: true

module Frontend
  module TemplateStorage
    module_function

    def root
      Pathname(default_root)
    end

    def default_root
      if Rails.env.test?
        Rails.root.join("tmp", "templates").to_s
      else
        ENV.fetch("MCWEB_TEMPLATE_DIR", "/var/lib/mcweb/templates")
      end
    end

    def path_for(key)
      root.join(key.to_s)
    end

    def ensure_root!
      FileUtils.mkdir_p(root)
    end
  end
end
