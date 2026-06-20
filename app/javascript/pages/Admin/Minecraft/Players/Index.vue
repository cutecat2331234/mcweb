<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { formatRelativeTime } from '@/lib/relativeTime'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  players: Array<{
    username: string
    player_id: string
    player_uuid?: string
    ingame_online: boolean
    ingame_server: string
    ingame_server_id: string
    website_online: boolean
    joined_at?: string
    linked_user?: { id: string; username: string } | null
  }>
  kickUrl: string
  backUrl: string
}>()

const { t, locale } = useI18n()

function joinedLabel(joinedAt?: string) {
  if (!joinedAt) return '—'
  return formatRelativeTime(joinedAt, locale.value)
}

function kickPlayer(player: (typeof props.players)[number]) {
  if (!window.confirm(t('adminMinecraft.confirmKick', { name: player.username }))) return
  router.post(props.kickUrl, {
    username: player.username,
    uuid: player.player_uuid,
    server_id: player.ingame_server_id,
  })
}
</script>

<template>
  <PageHeader :title="title" />
  <div class="overflow-x-auto">
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b text-left">
          <th class="p-2">{{ t('adminMinecraft.colName') }}</th>
          <th class="p-2">{{ t('adminMinecraft.ingameServer') }}</th>
          <th class="p-2">{{ t('adminMinecraft.ingameOnline') }}</th>
          <th class="p-2">{{ t('adminMinecraft.websiteOnline') }}</th>
          <th class="p-2">{{ t('adminMinecraft.joinedAt') }}</th>
          <th class="p-2">{{ t('adminMinecraft.linkedAccount') }}</th>
          <th class="p-2">{{ t('adminMinecraft.actions') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="p in players" :key="p.player_id" class="border-b">
          <td class="p-2">{{ p.username }}</td>
          <td class="p-2">{{ p.ingame_server }}</td>
          <td class="p-2">{{ p.ingame_online ? '✓' : '—' }}</td>
          <td class="p-2">{{ p.website_online ? '✓' : '—' }}</td>
          <td class="p-2 text-muted-foreground" :title="p.joined_at">{{ joinedLabel(p.joined_at) }}</td>
          <td class="p-2">
            <Link
              v-if="p.linked_user"
              :href="adminRoutes.user(p.linked_user.id)"
              class="text-primary hover:underline"
            >
              {{ p.linked_user.username }}
            </Link>
            <span v-else>—</span>
          </td>
          <td class="p-2">
            <Button v-if="p.ingame_online" type="button" size="sm" variant="outline" @click="kickPlayer(p)">
              {{ t('adminMinecraft.kickPlayer') }}
            </Button>
          </td>
        </tr>
        <tr v-if="!players.length">
          <td colspan="7" class="p-4 text-muted-foreground">{{ t('adminMinecraft.noPlayersOnline') }}</td>
        </tr>
      </tbody>
    </table>
  </div>
  <Button variant="ghost" class="mt-4" as-child>
    <a :href="backUrl">{{ t('adminMinecraft.backToServers') }}</a>
  </Button>
</template>
