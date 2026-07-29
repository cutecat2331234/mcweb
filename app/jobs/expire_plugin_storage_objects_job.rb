# frozen_string_literal: true

class ExpirePluginStorageObjectsJob < ApplicationJob
  queue_as :maintenance

  def perform
    PluginStorageObject.where(expires_at: ..Time.current).find_each(&:destroy!)
  end
end
