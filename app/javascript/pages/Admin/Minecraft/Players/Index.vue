<script setup lang="ts">
import { computed } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
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
const columns = computed(() => [
  { title: t('adminMinecraft.colName'), dataIndex: 'username', fixed: 'left', width: 160 },
  { title: t('adminMinecraft.ingameServer'), dataIndex: 'ingame_server', width: 160 },
  { title: t('adminMinecraft.ingameOnline'), slotName: 'ingameOnline', width: 130 },
  { title: t('adminMinecraft.websiteOnline'), slotName: 'websiteOnline', width: 130 },
  { title: t('adminMinecraft.joinedAt'), slotName: 'joinedAt', width: 180 },
  { title: t('adminMinecraft.linkedAccount'), slotName: 'linkedAccount', width: 180 },
  { title: t('adminMinecraft.actions'), slotName: 'actions', width: 120 },
])

function joinedLabel(joinedAt?: string) {
  if (!joinedAt) return '—'
  return formatRelativeTime(joinedAt, locale.value)
}

function kickPlayer(player: (typeof props.players)[number]) {
  Modal.warning({
    title: t('adminMinecraft.kickPlayer'),
    content: t('adminMinecraft.confirmKick', { name: player.username }),
    okText: t('adminMinecraft.kickPlayer'),
    cancelText: t('common.cancel'),
    hideCancel: false,
    okButtonProps: { status: 'danger' },
    onOk: () => {
      router.post(props.kickUrl, {
        username: player.username,
        uuid: player.player_uuid,
        server_id: player.ingame_server_id,
      })
    },
  })
}
</script>

<template>
  <a-page-header :title="title" :show-back="false">
    <template #extra>
      <a-button @click="router.visit(backUrl)">{{ t('adminMinecraft.backToServers') }}</a-button>
    </template>
  </a-page-header>
  <a-card :bordered="true">
    <a-table
      :columns="columns"
      :data="players"
      row-key="player_id"
      :pagination="false"
      :scroll="{ x: 1040 }"
    >
      <template #ingameOnline="{ record }">
        <a-tag :color="record.ingame_online ? 'green' : 'gray'">
          {{ record.ingame_online ? t('adminMinecraft.yes') : t('adminMinecraft.no') }}
        </a-tag>
      </template>
      <template #websiteOnline="{ record }">
        <a-tag :color="record.website_online ? 'green' : 'gray'">
          {{ record.website_online ? t('adminMinecraft.yes') : t('adminMinecraft.no') }}
        </a-tag>
      </template>
      <template #joinedAt="{ record }">
        <span :title="record.joined_at">{{ joinedLabel(record.joined_at) }}</span>
      </template>
      <template #linkedAccount="{ record }">
        <a-link
          v-if="record.linked_user"
          @click="router.visit(adminRoutes.user(record.linked_user.id))"
        >
          {{ record.linked_user.username }}
        </a-link>
        <span v-else>—</span>
      </template>
      <template #actions="{ record }">
        <a-button
          v-if="record.ingame_online"
          type="text"
          status="danger"
          size="small"
          @click="kickPlayer(record)"
        >
          {{ t('adminMinecraft.kickPlayer') }}
        </a-button>
      </template>
      <template #empty>
        <a-empty :description="t('adminMinecraft.noPlayersOnline')" />
      </template>
    </a-table>
  </a-card>
</template>
