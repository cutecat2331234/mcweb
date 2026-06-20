# frozen_string_literal: true

module Commerce
  module SkippedItemLabel
    module_function

    def for_product(product_name, reason)
      I18n.t("mcweb.commerce.skipped.#{reason}", product: product_name)
    end

    def compare_limit(count)
      I18n.t("mcweb.commerce.skipped.compare_limit_summary", count: count)
    end
  end
end
