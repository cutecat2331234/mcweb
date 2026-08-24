import { routes } from '@/lib/routes'
import { documentFrontendApplicationId } from '@/lib/frontendApplications'
import { performSharedAction, SharedActionError } from '@/lib/sharedAction'
import { navigateFrontendDocument } from '@/lib/applicationNavigation'
import { confirmUnsavedNavigation } from '@/lib/unsavedForms'

type SafeSignOutHooks = {
  onStart?: () => void
  onFinish?: () => void
}

export async function safeSignOut(hooks: SafeSignOutHooks = {}) {
  if (!confirmUnsavedNavigation()) return
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
    try {
      navigateFrontendDocument(routes.signedOut)
    } catch {
      window.location.assign(routes.signedOut)
    }
  }

  hooks.onStart?.()

  try {
    await performSharedAction(documentFrontendApplicationId(), routes.signOut, {
      method: 'DELETE',
    })
    visitSafePublicPage()
  } catch (error) {
    if (error instanceof SharedActionError && error.recoveryStarted) return
    if (fallbackStarted) throw error
    visitSafePublicPage()
  } finally {
    finish()
  }
}
