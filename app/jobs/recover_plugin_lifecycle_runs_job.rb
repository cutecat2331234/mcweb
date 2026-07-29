# frozen_string_literal: true

require "mcweb/plugins/marketplace/lifecycle_store"

class RecoverPluginLifecycleRunsJob < ApplicationJob
  queue_as :plugins

  def perform
    Mcweb::Plugins::Marketplace::LifecycleStore.new.recover_stale!
  end
end
