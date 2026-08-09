<script setup lang="ts">
import { computed, ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { formatRelativeTime } from '@/lib/relativeTime'

defineOptions({ layout: AdminLayout })

type AccountSummary = {
  linkId: number
  username: string
  uuid: string
  active: boolean
  primary: boolean
  avatarUrl: string
}

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
  primaryAccountPermissions: {
    review: boolean
    switchForUser: boolean
  }
  primaryAccountRequests: Array<{
    id: number
    member: { id: string; username: string }
    sourceAccount?: AccountSummary | null
    targetAccount?: AccountSummary | null
    status: 'pending' | 'approved' | 'rejected' | 'expired' | 'cancelled'
    reason: string
    decisionReason?: string | null
    requestedAt: string
    expiresAt: string
    resolvedAt?: string | null
    lockVersion: number
    decisionUrl: string
  }>
  boundAccounts: Array<{
    linkId: number
    member: { id: string; username: string }
    username: string
    uuid: string
    identityType: string
    primary: boolean
    avatarUrl: string
    switchUrl: string
  }>
}>()

const { t, locale } = useI18n()
const decisionReasons = ref<Record<number, string>>({})
const decidingRequestId = ref<number | null>(null)
const overrideReason = ref('')
const switchingLinkId = ref<number | null>(null)

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

function dateLabel(value?: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
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

function decideRequest(
  requestRecord: (typeof props.primaryAccountRequests)[number],
  decision: 'approve' | 'reject',
) {
  const reason = decisionReasons.value[requestRecord.id]?.trim() || ''
  if (decision === 'reject' && !reason) return

  router.patch(requestRecord.decisionUrl, {
    decision,
    reason,
    lock_version: requestRecord.lockVersion,
    idempotency_key: crypto.randomUUID(),
  }, {
    preserveScroll: true,
    onStart: () => {
      decidingRequestId.value = requestRecord.id
    },
    onFinish: () => {
      decidingRequestId.value = null
    },
  })
}

function switchForUser(account: (typeof props.boundAccounts)[number]) {
  if (account.primary || !overrideReason.value.trim() || switchingLinkId.value !== null) return

  router.post(account.switchUrl, {
    identity_link_id: account.linkId,
    reason: overrideReason.value.trim(),
    idempotency_key: crypto.randomUUID(),
  }, {
    preserveScroll: true,
    onStart: () => {
      switchingLinkId.value = account.linkId
    },
    onFinish: () => {
      switchingLinkId.value = null
    },
  })
}

function statusColor(status: string) {
  if (status === 'approved') return 'green'
  if (status === 'rejected') return 'red'
  if (status === 'pending') return 'orange'
  return 'gray'
}
</script>

<template>
  <a-page-header :title="title" :show-back="false">
    <template #extra>
      <a-button @click="router.visit(backUrl)">{{ t('adminMinecraft.backToServers') }}</a-button>
    </template>
  </a-page-header>

  <a-space direction="vertical" size="large" fill>
    <a-card
      v-if="primaryAccountPermissions.review"
      :title="t('adminMinecraft.primaryAccountRequestsTitle')"
      :bordered="true"
    >
      <a-table
        :data="primaryAccountRequests"
        row-key="id"
        :pagination="{ pageSize: 20 }"
        :scroll="{ x: 1260 }"
      >
        <template #columns>
          <a-table-column :title="t('adminMinecraft.linkedAccount')" :width="170">
            <template #cell="{ record }">
              <a-link @click="router.visit(adminRoutes.user(record.member.id))">
                {{ record.member.username }}
              </a-link>
            </template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.primaryAccountChange')" :width="280">
            <template #cell="{ record }">
              <a-space>
                <span>{{ record.sourceAccount?.username || '—' }}</span>
                <span>→</span>
                <a-space v-if="record.targetAccount" :size="6">
                  <a-avatar
                    :size="28"
                    shape="square"
                    :image-url="record.targetAccount.avatarUrl"
                  />
                  <span>{{ record.targetAccount.username }}</span>
                </a-space>
                <span v-else>—</span>
              </a-space>
            </template>
          </a-table-column>
          <a-table-column data-index="reason" :title="t('adminMinecraft.requestReason')" :width="220" />
          <a-table-column :title="t('adminMinecraft.requestStatus')" :width="120">
            <template #cell="{ record }">
              <a-tag :color="statusColor(record.status)">
                {{ t(`adminMinecraft.primaryRequestStatuses.${record.status}`) }}
              </a-tag>
            </template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.requestExpiresAt')" :width="190">
            <template #cell="{ record }">{{ dateLabel(record.expiresAt) }}</template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.reviewReason')" :width="260">
            <template #cell="{ record }">
              <a-textarea
                v-if="record.status === 'pending'"
                v-model="decisionReasons[record.id]"
                :max-length="2000"
                :placeholder="t('adminMinecraft.reviewReasonPlaceholder')"
              />
              <span v-else>{{ record.decisionReason || '—' }}</span>
            </template>
          </a-table-column>
          <a-table-column :title="t('adminMinecraft.actions')" fixed="right" :width="190">
            <template #cell="{ record }">
              <a-space v-if="record.status === 'pending'">
                <a-button
                  type="primary"
                  size="small"
                  :loading="decidingRequestId === record.id"
                  @click="decideRequest(record, 'approve')"
                >
                  {{ t('adminMinecraft.approvePrimaryRequest') }}
                </a-button>
                <a-button
                  status="danger"
                  size="small"
                  :disabled="!decisionReasons[record.id]?.trim()"
                  :loading="decidingRequestId === record.id"
                  @click="decideRequest(record, 'reject')"
                >
                  {{ t('adminMinecraft.rejectPrimaryRequest') }}
                </a-button>
              </a-space>
              <span v-else>—</span>
            </template>
          </a-table-column>
        </template>
        <template #empty>
          <a-empty :description="t('adminMinecraft.noPrimaryAccountRequests')" />
        </template>
      </a-table>
    </a-card>

    <a-card
      v-if="primaryAccountPermissions.switchForUser"
      :title="t('adminMinecraft.primaryAccountOverrideTitle')"
      :bordered="true"
    >
      <a-space direction="vertical" size="large" fill>
        <a-alert type="warning" show-icon>
          {{ t('adminMinecraft.primaryAccountOverrideDescription') }}
        </a-alert>
        <a-form-item
          :label="t('adminMinecraft.overrideReason')"
          :help="t('adminMinecraft.overrideReasonHelp')"
          required
        >
          <a-textarea
            v-model="overrideReason"
            :max-length="2000"
            show-word-limit
            :placeholder="t('adminMinecraft.overrideReasonPlaceholder')"
          />
        </a-form-item>
        <a-table
          :data="boundAccounts"
          row-key="linkId"
          :pagination="{ pageSize: 25 }"
          :scroll="{ x: 920 }"
        >
          <template #columns>
            <a-table-column :title="t('adminMinecraft.linkedAccount')" :width="180">
              <template #cell="{ record }">
                <a-link @click="router.visit(adminRoutes.user(record.member.id))">
                  {{ record.member.username }}
                </a-link>
              </template>
            </a-table-column>
            <a-table-column :title="t('adminMinecraft.minecraftAccount')" :width="240">
              <template #cell="{ record }">
                <a-space>
                  <a-avatar :size="36" shape="square" :image-url="record.avatarUrl" />
                  <a-space direction="vertical" :size="1">
                    <span>{{ record.username }}</span>
                    <a-typography-text code copyable>{{ record.uuid }}</a-typography-text>
                  </a-space>
                </a-space>
              </template>
            </a-table-column>
            <a-table-column data-index="identityType" :title="t('adminMinecraft.identityType')" />
            <a-table-column :title="t('adminMinecraft.requestStatus')" :width="130">
              <template #cell="{ record }">
                <a-tag :color="record.primary ? 'green' : 'gray'">
                  {{
                    record.primary
                      ? t('minecraft.link.primaryAccount')
                      : t('adminMinecraft.secondaryAccount')
                  }}
                </a-tag>
              </template>
            </a-table-column>
            <a-table-column :title="t('adminMinecraft.actions')" fixed="right" :width="170">
              <template #cell="{ record }">
                <a-button
                  v-if="!record.primary"
                  type="primary"
                  size="small"
                  :disabled="!overrideReason.trim()"
                  :loading="switchingLinkId === record.linkId"
                  @click="switchForUser(record)"
                >
                  {{ t('adminMinecraft.setPrimaryForUser') }}
                </a-button>
                <span v-else>—</span>
              </template>
            </a-table-column>
          </template>
        </a-table>
      </a-space>
    </a-card>

    <a-card :bordered="true" :title="t('adminMinecraft.onlinePlayersTitle')">
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
  </a-space>
</template>
