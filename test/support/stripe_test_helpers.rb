# frozen_string_literal: true

class StripeTestSessionsService
  attr_reader :requests

  def initialize(session)
    @session = session
    @requests = []
  end

  def create(params, options = {})
    @requests << { params: params, options: options }
    @session
  end
end

class StripeTestRefundsService
  attr_reader :create_requests, :retrieve_requests

  def initialize(created_refund: nil, retrieved_refund: nil)
    @created_refund = created_refund
    @retrieved_refund = retrieved_refund || created_refund
    @create_requests = []
    @retrieve_requests = []
  end

  def create(params, options = {})
    @create_requests << { params: params, options: options }
    @created_refund
  end

  def retrieve(provider_refund_id)
    @retrieve_requests << provider_refund_id
    @retrieved_refund
  end
end

module StripeTestHelpers
  DEFAULT_STRIPE_TEST_ACCOUNT_ID = "acct_1234567890ABCDEF"

  def mark_stripe_provider_connection_tested!(
    config,
    account_id: DEFAULT_STRIPE_TEST_ACCOUNT_ID,
    actor: nil,
    tested_at: Time.current
  )
    config.update!(
      account_fingerprint:
        Payments::StripeConnectionProbe.account_fingerprint(account_id),
      last_connection_test_status: "success",
      last_connection_test_error_code: nil,
      last_connection_test_mode: config.effective_mode,
      last_connection_tested_at: tested_at,
      last_connection_tested_by: actor,
      last_connection_test_credential_revision: config.credential_revision
    )
    config
  end

  def with_stripe_client(client)
    singleton = Stripe::StripeClient.singleton_class
    had_own_new = singleton.instance_methods(false).include?(:new)
    original_new = singleton.instance_method(:new) if had_own_new
    singleton.define_method(:new) { |*| client }
    yield
  ensure
    if had_own_new
      singleton.define_method(:new, original_new)
    else
      singleton.remove_method(:new)
    end
  end

  def build_stripe_test_client(
    session: default_stripe_checkout_session,
    created_refund: nil,
    retrieved_refund: nil
  )
    sessions = StripeTestSessionsService.new(session)
    refunds = StripeTestRefundsService.new(
      created_refund: created_refund,
      retrieved_refund: retrieved_refund
    )
    client = OpenStruct.new(
      v1: OpenStruct.new(
        checkout: OpenStruct.new(sessions: sessions),
        refunds: refunds
      )
    )

    [ client, sessions, refunds ]
  end

  def default_stripe_checkout_session
    {
      "id" => "cs_test_#{SecureRandom.hex(8)}",
      "url" => "https://checkout.stripe.com/c/pay/#{SecureRandom.hex(12)}",
      "livemode" => false
    }
  end

  def stripe_webhook_signature(payload, secret, timestamp: Time.current)
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    Stripe::Webhook::Signature.generate_header(timestamp, signature)
  end
end
