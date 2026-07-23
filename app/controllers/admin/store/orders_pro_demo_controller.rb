# frozen_string_literal: true

module Admin
  module Store
    # POC — Element Plus ProTable sample for the store orders list.
    #
    # Mounted at /admin/store/orders_pro_demo, fully isolated from the live
    # orders page (which is rendered by Admin/Generic/Index.vue). Uses a small
    # deterministic demo dataset so the redesign screenshot is stable regardless
    # of DB contents, and performs NO database writes. Safe to delete once the
    # redesign direction is signed off.
    class OrdersProDemoController < BaseController
      before_action -> { require_permission("store.orders.read") }

      PER_PAGE = 8

      def index
        rows = filtered_rows
        total = rows.size
        pages = total.zero? ? 1 : (total.to_f / PER_PAGE).ceil
        page = params[:page].to_i
        page = 1 if page < 1
        page = pages if page > pages
        window = rows[(page - 1) * PER_PAGE, PER_PAGE] || []

        render inertia: "Admin/Store/Orders/IndexProDemo", props: {
          title: "商城订单",
          subtitle: "Element Plus ProTable 重做样板（演示数据，不影响真实订单）",
          columns: [
            { key: "order_number", label: "订单号", link: false, minWidth: 150 },
            { key: "customer", label: "客户", minWidth: 120 },
            { key: "status", label: "状态", width: 110, align: "center" },
            { key: "payment_status", label: "支付", width: 100, align: "center" },
            { key: "total", label: "金额", width: 130, align: "right" },
            { key: "created_at", label: "下单时间", minWidth: 160, sortable: true }
          ],
          rows: window,
          pagination: {
            page: page,
            pages: pages,
            count: total,
            from: total.zero? ? 0 : (page - 1) * PER_PAGE + 1,
            to: [ page * PER_PAGE, total ].min,
            prev: page > 1 ? page_url(page - 1) : nil,
            next: page < pages ? page_url(page + 1) : nil
          },
          statusOptions: status_options,
          currentStatus: params[:status].to_s,
          query: params[:q].to_s,
          bulkActionUrl: admin_store_orders_pro_demo_bulk_path,
          bulkActions: [
            { label: "标记已支付", action: "mark_paid", type: "success" },
            { label: "标记已发货", action: "mark_fulfilled", type: "primary" },
            { label: "取消订单", action: "cancel", type: "danger" }
          ]
        }
      end

      # Demonstrates the full Inertia bulk round-trip without touching the DB.
      def bulk
        ids = Array(params[:ids])
        action = params[:action_type].to_s
        destination = safe_local_path(params[:return_to]) || admin_store_orders_pro_demo_path
        redirect_to destination,
                    notice: "演示:已对 #{ids.size} 个订单执行「#{action}」(样板页不写入数据库)"
      end

      private

      def page_url(target)
        admin_store_orders_pro_demo_path(request.query_parameters.merge(page: target))
      end

      def status_options
        [
          { label: "全部", value: "" },
          { label: order_status_label("pending"), value: "pending" },
          { label: order_status_label("paid"), value: "paid" },
          { label: order_status_label("processing"), value: "processing" },
          { label: order_status_label("completed"), value: "completed" },
          { label: order_status_label("cancelled"), value: "cancelled" },
          { label: order_status_label("refunded"), value: "refunded" }
        ]
      end

      def filtered_rows
        rows = demo_rows
        if params[:status].present?
          rows = rows.select { |r| r[:status] == params[:status] }
        end
        if params[:q].present?
          needle = params[:q].to_s.downcase
          rows = rows.select { |r| r[:order_number].downcase.include?(needle) }
        end
        rows
      end

      PAYMENT_LABELS = {
        "paid" => "已支付",
        "unpaid" => "未支付",
        "pending" => "待支付",
        "refunded" => "已退款",
        "failed" => "支付失败"
      }.freeze

      # Deterministic showcase covering every el-tag color bucket.
      DEMO_SEED = [
        [ "MC-20260716-0012", "SteveCrafter", "completed", "paid",     "¥ 128.00", "2026-07-16 14:32" ],
        [ "MC-20260716-0011", "AlexZ",        "paid",      "paid",     "¥ 68.00",  "2026-07-16 11:05" ],
        [ "MC-20260715-0044", "NotchFan",     "fulfilling", "paid",     "¥ 245.00", "2026-07-15 22:18" ],
        [ "MC-20260715-0043", "EnderQueen",   "processing", "paid",     "¥ 32.00",  "2026-07-15 19:47" ],
        [ "MC-20260715-0041", "RedstoneGuru", "pending",   "unpaid",   "¥ 512.00", "2026-07-15 16:03" ],
        [ "MC-20260714-0098", "DiamondMax",   "awaiting_payment", "pending", "¥ 18.00", "2026-07-14 20:55" ],
        [ "MC-20260714-0097", "PixelKnight",  "fulfilled", "paid",     "¥ 99.00",  "2026-07-14 13:22" ],
        [ "MC-20260714-0090", "CreeperSlayer", "cancelled", "unpaid",   "¥ 156.00", "2026-07-14 09:41" ],
        [ "MC-20260713-0210", "MobHunter",    "refunded",  "refunded", "¥ 74.00",  "2026-07-13 18:30" ],
        [ "MC-20260713-0208", "SkyWalkerMC",  "failed",    "failed",   "¥ 260.00", "2026-07-13 15:12" ],
        [ "MC-20260713-0205", "GoldDigger",   "completed", "paid",     "¥ 42.00",  "2026-07-13 10:08" ],
        [ "MC-20260712-0177", "NetherLord",   "paid",      "paid",     "¥ 388.00", "2026-07-12 21:44" ],
        [ "MC-20260712-0175", "VillagerJoe",  "processing", "paid",     "¥ 55.00",  "2026-07-12 17:19" ],
        [ "MC-20260712-0170", "ObsidianOwl",  "completed", "paid",     "¥ 210.00", "2026-07-12 08:26" ]
      ].freeze

      def demo_rows
        DEMO_SEED.each_with_index.map do |(number, customer, status, payment, total, created_at), index|
          {
            publicId: "demo-#{index + 1}",
            order_number: number,
            customer: customer,
            status: status,
            status_label: order_status_label(status),
            payment_status: payment,
            payment_label: PAYMENT_LABELS.fetch(payment, payment.humanize),
            total: total,
            created_at: created_at
          }
        end
      end
    end
  end
end
