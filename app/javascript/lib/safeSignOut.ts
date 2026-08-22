import { router } from '@inertiajs/vue3'
import { routes } from '@/lib/routes'

type SafeSignOutHooks = {
  onStart?: () => void
  onFinish?: () => void
}

export function safeSignOut(hooks: SafeSignOutHooks = {}) {
  let fallbackStarted = false
  let finished = false

  const finish = () => {
    if (finished) return

    finished = true
    hooks.onFinish?.()
  }
  const visitSafePublicPage = () => {
    if (fallbackStarted) return

    fallbackStarted = true
    finish()
    window.location.assign(routes.signedOut)
  }

  hooks.onStart?.()

  try {
    router.delete(routes.signOut, {
      preserveState: false,
      onSuccess: visitSafePublicPage,
      onError: visitSafePublicPage,
      onCancel: visitSafePublicPage,
      onHttpException: visitSafePublicPage,
      onNetworkError: visitSafePublicPage,
      onFinish: finish,
    })
  } catch {
    visitSafePublicPage()
  }
}
