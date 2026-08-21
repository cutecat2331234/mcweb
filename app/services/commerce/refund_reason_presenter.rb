# frozen_string_literal: true

module Commerce
  module RefundReasonPresenter
    module_function

    def label(refund)
      if Commerce::Refund::REASON_KINDS.include?(refund.reason_kind)
        I18n.t("mcweb.labels.refund_reasons.#{refund.reason_kind}")
      else
        refund.reason
      end
    end
  end
end
