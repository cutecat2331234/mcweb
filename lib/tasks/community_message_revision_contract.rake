# frozen_string_literal: true

namespace :db do
  namespace :community_message_revisions do
    desc "Show whether encrypted private-message revision history is finalized"
    task status: :environment do
      contract = Mcweb::Migrations::CommunityMessageRevisionContract.new
      puts(contract.finalized? ? "finalized" : "pending")
    end

    desc "Finalize encrypted private-message revisions after the new application is live"
    task finalize: :environment do
      result = Mcweb::Migrations::CommunityMessageRevisionContract.new.call
      puts(
        "finalized=#{result.fetch(:finalized)} " \
        "preflight_inserted=#{result.fetch(:preflight_inserted)} " \
        "final_inserted=#{result.fetch(:final_inserted)}"
      )
    end
  end
end
