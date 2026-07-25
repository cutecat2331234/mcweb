import assert from 'node:assert/strict'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { extname, join, resolve } from 'node:path'
import test from 'node:test'

const root = process.cwd()

function source(path: string): string {
  return readFileSync(resolve(root, path), 'utf8')
}

function sourceFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name)
    if (entry.isDirectory()) return sourceFiles(path)
    return ['.ts', '.vue', '.js'].includes(extname(entry.name)) ? [path] : []
  })
}

test('CE frontend contains no WebSocket or Action Cable client', () => {
  const frontend = sourceFiles(resolve(root, 'app/javascript'))
    .map((path) => readFileSync(path, 'utf8'))
    .join('\n')

  assert.doesNotMatch(frontend, /\bnew\s+WebSocket\b/)
  assert.doesNotMatch(frontend, /\/cable\b/)
  assert.doesNotMatch(
    frontend,
    /useNotificationStream|useConversationTyping|AuthenticatedNotificationStream/,
  )
  assert.equal(existsSync(resolve(root, 'app/javascript/lib/useNotificationStream.ts')), false)
  assert.equal(existsSync(resolve(root, 'app/javascript/lib/useConversationTyping.ts')), false)
})

test('notification count stays server-driven without a live subscription', () => {
  const portalLayout = source('app/javascript/layouts/PortalLayout.vue')

  assert.match(
    portalLayout,
    /notificationUnreadCount\s*=\s*computed\(\(\)\s*=>\s*notifications\.value\?\.unread_count\s*\?\?\s*0\)/,
  )
  assert.doesNotMatch(portalLayout, /liveUnreadCount|useNotificationStream/)
})

test('private messages retain persisted rendering, submit, and manual refresh', () => {
  const messagePage = source('app/javascript/pages/Community/Messages/Show.vue')

  assert.match(messagePage, /v-for="msg in messages"/)
  assert.match(
    messagePage,
    /router\.reload\(\{\s*only:\s*\['messages', 'pagination'\]\s*\}\)/,
  )
  assert.match(
    messagePage,
    /form\.post\(`\$\{routes\.app\}\/forum\/conversations\/\$\{props\.conversation\.id\}\/messages`/,
  )
  assert.doesNotMatch(
    messagePage,
    /messageList|typingUsername|notifyTyping|onLiveMessage|current_user_id/,
  )
})
