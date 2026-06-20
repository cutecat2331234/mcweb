# frozen_string_literal: true

module Frontend
  module PathContainment
    module_function

    def within_root?(file, root)
      file = Pathname(file).cleanpath
      root = Pathname(root).cleanpath
      file == root || file.to_s.start_with?("#{root}#{File::SEPARATOR}")
    end
  end
end
