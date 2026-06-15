# frozen_string_literal: true

module Commerce
  module TrackingUrl
    module_function

    def for_order(order)
      return nil if order.tracking_number.blank?

      carrier = order.shipping_carrier.to_s.downcase
      case carrier
      when "sf", "shunfeng", "顺丰"
        "https://www.sf-express.com/cn/sc/dynamic_function/waybill/#search/bill-number/#{ERB::Util.url_encode(order.tracking_number)}"
      when "yt", "yuantong", "圆通"
        "https://www.yto.net.cn/tracesearch.html?#{order.tracking_number}"
      when "sto", "shentong", "申通"
        "https://www.sto.cn/querybill?billcode=#{ERB::Util.url_encode(order.tracking_number)}"
      else
        "https://www.kuaidi100.com/chaxun?nu=#{ERB::Util.url_encode(order.tracking_number)}"
      end
    end
  end
end
