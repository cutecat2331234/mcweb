import { ref } from 'vue'
import { routes } from '@/lib/routes'
import { readCsrfToken } from '@/lib/csrf'

// Web Push enable/disable: registers the service worker, subscribes via the
// PushManager using the server VAPID public key, and syncs the subscription.
export function useWebPush() {
  const supported = typeof navigator !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window
  const busy = ref(false)
  const enabled = ref(false)

  function urlBase64ToUint8Array(base64String: string): Uint8Array {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
    const raw = atob(base64)
    const output = new Uint8Array(raw.length)
    for (let i = 0; i < raw.length; i += 1) output[i] = raw.charCodeAt(i)
    return output
  }

  async function refresh() {
    if (!supported) return
    try {
      const reg = await navigator.serviceWorker.getRegistration()
      const sub = await reg?.pushManager.getSubscription()
      enabled.value = !!sub
    } catch {
      enabled.value = false
    }
  }

  async function enable(): Promise<boolean> {
    if (!supported || busy.value) return false
    busy.value = true
    try {
      const permission = await Notification.requestPermission()
      if (permission !== 'granted') return false

      const reg = await navigator.serviceWorker.register('/sw.js')
      const res = await fetch(`${routes.app}/forum/push/public_key`, { credentials: 'same-origin' })
      const { public_key: publicKey } = await res.json()

      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(publicKey),
      })

      await fetch(`${routes.app}/forum/push/subscribe`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': readCsrfToken() },
        credentials: 'same-origin',
        body: JSON.stringify({ subscription: sub.toJSON() }),
      })
      enabled.value = true
      return true
    } catch {
      return false
    } finally {
      busy.value = false
    }
  }

  async function disable(): Promise<void> {
    if (!supported || busy.value) return
    busy.value = true
    try {
      const reg = await navigator.serviceWorker.getRegistration()
      const sub = await reg?.pushManager.getSubscription()
      if (sub) {
        await fetch(`${routes.app}/forum/push/unsubscribe`, {
          method: 'DELETE',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': readCsrfToken() },
          credentials: 'same-origin',
          body: JSON.stringify({ endpoint: sub.endpoint }),
        })
        await sub.unsubscribe()
      }
      enabled.value = false
    } catch {
      // ignore
    } finally {
      busy.value = false
    }
  }

  return { supported, busy, enabled, enable, disable, refresh }
}
