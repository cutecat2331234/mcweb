# frozen_string_literal: true

module Identity
  module AccountClosure
    Context = Data.define(:user, :closure_mode, :reason, :at)
  end
end
