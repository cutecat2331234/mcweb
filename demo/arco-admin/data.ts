export interface DemoStat {
  key: string
  label: string
  value: string
  trend: string
  trend_type: 'up' | 'down' | 'warn'
  accent: 'primary' | 'success' | 'warning' | 'info'
}

export interface DemoRow {
  id: number
  order_number: string
  customer: string
  status: string
  status_label: string
  total: string
  created_at: string
}

export const demoStats: DemoStat[] = [
  { key: 'orders', label: '总订单', value: '1,284', trend: '+12.5%', trend_type: 'up', accent: 'primary' },
  { key: 'pending', label: '待处理', value: '23', trend: '需跟进', trend_type: 'warn', accent: 'warning' },
  { key: 'users', label: '注册用户', value: '5,672', trend: '+3.2%', trend_type: 'up', accent: 'info' },
  { key: 'revenue', label: '本月收入', value: '¥ 48,690', trend: '+8.1%', trend_type: 'up', accent: 'success' },
]

export const demoTable: DemoRow[] = [
  { id: 1, order_number: 'MC-20260717-0021', customer: 'SteveCrafter', status: 'completed', status_label: '已完成', total: '¥ 128.00', created_at: '2026-07-17 14:32' },
  { id: 2, order_number: 'MC-20260717-0020', customer: 'EnderQueen', status: 'processing', status_label: '处理中', total: '¥ 32.00', created_at: '2026-07-17 13:18' },
  { id: 3, order_number: 'MC-20260717-0018', customer: 'RedstoneGuru', status: 'pending', status_label: '待支付', total: '¥ 512.00', created_at: '2026-07-17 11:05' },
  { id: 4, order_number: 'MC-20260716-0099', customer: 'PixelKnight', status: 'paid', status_label: '已支付', total: '¥ 99.00', created_at: '2026-07-16 22:41' },
  { id: 5, order_number: 'MC-20260716-0095', customer: 'CreeperSlayer', status: 'cancelled', status_label: '已取消', total: '¥ 156.00', created_at: '2026-07-16 20:12' },
  { id: 6, order_number: 'MC-20260716-0090', customer: 'MobHunter', status: 'refunded', status_label: '已退款', total: '¥ 74.00', created_at: '2026-07-16 18:55' },
]
