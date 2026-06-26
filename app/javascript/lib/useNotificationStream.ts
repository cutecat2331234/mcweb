import { onMounted, onUnmounted } from 'vue'

// Minimal ActionCable client over the native WebSocket API (no extra npm
// dependency). Subscribes to the per-user notifications stream and invokes
// `onMessage` for each broadcast. Reconnects on drop. Safe no-op if /cable
// is unreachable.
export function useNotificationStream(onMessage: (data: Record<string, unknown>) => void) {
  let socket: WebSocket | null = null
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null
  let stopped = false

  const identifier = JSON.stringify({ channel: 'Community::NotificationsChannel' })

  function connect() {
    if (stopped) return
    try {
      const proto = location.protocol === 'https:' ? 'wss' : 'ws'
      socket = new WebSocket(`${proto}://${location.host}/cable`)
    } catch {
      scheduleReconnect()
      return
    }

    socket.onopen = () => {
      socket?.send(JSON.stringify({ command: 'subscribe', identifier }))
    }

    socket.onmessage = (event) => {
      let payload: { type?: string; identifier?: string; message?: Record<string, unknown> }
      try {
        payload = JSON.parse(event.data)
      } catch {
        return
      }
      if (payload.type === 'ping' || payload.type === 'welcome' || payload.type === 'confirm_subscription') return
      if (payload.identifier === identifier && payload.message) {
        onMessage(payload.message)
      }
    }

    socket.onclose = () => {
      socket = null
      if (!stopped) scheduleReconnect()
    }

    socket.onerror = () => {
      socket?.close()
    }
  }

  function scheduleReconnect() {
    if (reconnectTimer || stopped) return
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null
      connect()
    }, 5000)
  }

  onMounted(connect)
  onUnmounted(() => {
    stopped = true
    if (reconnectTimer) clearTimeout(reconnectTimer)
    socket?.close()
  })
}
