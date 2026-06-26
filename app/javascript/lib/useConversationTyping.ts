import { onMounted, onUnmounted, ref } from 'vue'

// A live message pushed over the conversation channel (kind: "message").
export interface LiveMessage {
  id: number
  body: string
  body_html: string
  author: string
  author_id: number
  avatar_url: string
  created_at: string
}

// Ephemeral typing indicator over the native WebSocket API (ActionCable
// protocol), reusing the /cable endpoint. Sends "typing" signals (throttled)
// and exposes the username of another participant currently typing. Also relays
// live "message" broadcasts to an optional onMessage callback.
export function useConversationTyping(
  conversationId: number | string,
  selfUserId: number,
  onMessage?: (message: LiveMessage) => void,
) {
  const typingUsername = ref<string | null>(null)
  let socket: WebSocket | null = null
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null
  let clearTypingTimer: ReturnType<typeof setTimeout> | null = null
  let lastSentAt = 0
  let subscribed = false
  let stopped = false

  const identifier = JSON.stringify({ channel: 'Community::ConversationChannel', id: conversationId })

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
      let payload: {
        type?: string
        identifier?: string
        message?: {
          kind?: string
          typing?: boolean
          user_id?: number
          username?: string
          message?: LiveMessage
        }
      }
      try {
        payload = JSON.parse(event.data)
      } catch {
        return
      }
      if (payload.type === 'confirm_subscription' && payload.identifier === identifier) {
        subscribed = true
        return
      }
      if (payload.type === 'ping' || payload.type === 'welcome' || payload.type === 'reject_subscription') return
      if (payload.identifier !== identifier || !payload.message) return

      const data = payload.message
      // Live persisted message broadcast.
      if (data.kind === 'message' && data.message) {
        onMessage?.(data.message)
        return
      }
      // Ephemeral typing signal from another participant.
      if (data.typing && data.user_id !== selfUserId) {
        typingUsername.value = data.username ?? null
        if (clearTypingTimer) clearTimeout(clearTypingTimer)
        clearTypingTimer = setTimeout(() => { typingUsername.value = null }, 3500)
      }
    }

    socket.onclose = () => {
      socket = null
      subscribed = false
      if (!stopped) scheduleReconnect()
    }

    socket.onerror = () => { socket?.close() }
  }

  function scheduleReconnect() {
    if (reconnectTimer || stopped) return
    reconnectTimer = setTimeout(() => { reconnectTimer = null; connect() }, 5000)
  }

  // Call on composer input — throttled to at most once per 2s.
  function notifyTyping() {
    if (!subscribed || !socket || socket.readyState !== WebSocket.OPEN) return
    const now = Date.now()
    if (now - lastSentAt < 2000) return
    lastSentAt = now
    socket.send(JSON.stringify({ command: 'message', identifier, data: JSON.stringify({ action: 'typing' }) }))
  }

  onMounted(connect)
  onUnmounted(() => {
    stopped = true
    if (reconnectTimer) clearTimeout(reconnectTimer)
    if (clearTypingTimer) clearTimeout(clearTypingTimer)
    socket?.close()
  })

  return { typingUsername, notifyTyping }
}
