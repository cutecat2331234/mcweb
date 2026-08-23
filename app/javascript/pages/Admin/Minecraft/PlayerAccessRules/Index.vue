<script setup lang="ts">
import { computed, ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type Rule = {
  id: string
  type: 'whitelist' | 'ban'
  status: 'pending_apply' | 'active' | 'pending_revoke' | 'revoked' | 'failed'
  username: string
  playerUuid: string | null
  reason: string
  revokeReason: string | null
  server: { id: string; name: string }
  createdBy: string | null
  revokedBy: string | null
  expiresAt: string | null
  appliedAt: string | null
  revokedAt: string | null
  failedAt: string | null
  createdAt: string
  applyTaskStatus: string | null
  revokeTaskStatus: string | null
  lockVersion: number
  canRevoke: boolean
  revokeUrl: string
}

type Copy = {
  title: string
  subtitle: string
  open: string
  back: string
  createTitle: string
  historyTitle: string
  server: string
  serverPlaceholder: string
  connectorReady: string
  connectorOffline: string
  type: string
  username: string
  usernamePlaceholder: string
  playerUuid: string
  playerUuidPlaceholder: string
  reason: string
  reasonPlaceholder: string
  expiresAt: string
  optional: string
  submit: string
  noServers: string
  empty: string
  status: string
  target: string
  createdBy: string
  createdAt: string
  taskStatus: string
  actions: string
  revoke: string
  revokeTitle: string
  revokeDescription: string
  revokeReason: string
  revokeReasonPlaceholder: string
  cancel: string
  loadOlder: string
  ruleTypes: Record<string, string>
  statuses: Record<string, string>
  taskStatuses: Record<string, string>
}

const props = defineProps<{
  copy: Copy
  ruleTypes: Array<'whitelist' | 'ban'>
  servers: Array<{ id: string; name: string; status: string; connectorReady: boolean }>
  rules: Rule[]
  paths: { create: string; players: string; next: string | null }
}>()

const form = useForm({
  access_rule: {
    server_id: props.servers[0]?.id || '',
    rule_type: 'whitelist' as 'whitelist' | 'ban',
    username: '',
    player_uuid: '',
    reason: '',
    expires_at: '',
    idempotency_key: crypto.randomUUID(),
  },
})
const revokeRule = ref<Rule | null>(null)
const revokeReason = ref('')
const revoking = ref(false)

const canSubmit = computed(() => (
  Boolean(form.access_rule.server_id) &&
  /^[A-Za-z0-9_]{1,16}$/.test(form.access_rule.username.trim()) &&
  form.access_rule.reason.trim().length > 0 &&
  !form.processing
))

function submit() {
  if (!canSubmit.value) return
  form.post(props.paths.create, {
    preserveScroll: true,
    onSuccess: () => {
      form.access_rule.username = ''
      form.access_rule.player_uuid = ''
      form.access_rule.reason = ''
      form.access_rule.expires_at = ''
      form.access_rule.idempotency_key = crypto.randomUUID()
    },
  })
}

function openRevoke(rule: Rule) {
  revokeRule.value = rule
  revokeReason.value = ''
}

function closeRevoke() {
  if (revoking.value) return
  revokeRule.value = null
  revokeReason.value = ''
}

function confirmRevoke() {
  if (!revokeRule.value || !revokeReason.value.trim() || revoking.value) return false
  const rule = revokeRule.value
  revoking.value = true
  router.delete(rule.revokeUrl, {
    data: {
      reason: revokeReason.value.trim(),
      lock_version: rule.lockVersion,
      idempotency_key: crypto.randomUUID(),
    },
    preserveScroll: true,
    onSuccess: closeRevoke,
    onFinish: () => { revoking.value = false },
  })
  return false
}

function formatDate(value: string | null) {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString()
}

function statusColor(status: Rule['status']) {
  if (status === 'active') return 'green'
  if (status === 'pending_apply' || status === 'pending_revoke') return 'orange'
  if (status === 'failed') return 'red'
  return 'gray'
}
</script>

<template>
  <a-space direction="vertical" size="large" fill>
    <a-page-header :title="copy.title" :subtitle="copy.subtitle" :show-back="false">
      <template #extra>
        <a-button @click="router.visit(paths.players)">{{ copy.back }}</a-button>
      </template>
    </a-page-header>

    <a-alert v-if="servers.length === 0" type="warning" show-icon>
      {{ copy.noServers }}
    </a-alert>

    <a-card :title="copy.createTitle" :bordered="true">
      <a-form :model="form.access_rule" layout="vertical" @submit="submit">
        <a-grid :cols="{ xs: 1, sm: 1, md: 2, lg: 3 }" :col-gap="16" :row-gap="4">
          <a-grid-item>
            <a-form-item field="server_id" :label="copy.server" required>
              <a-select v-model="form.access_rule.server_id" :placeholder="copy.serverPlaceholder">
                <a-option v-for="server in servers" :key="server.id" :value="server.id">
                  {{ server.name }} · {{ server.connectorReady ? copy.connectorReady : copy.connectorOffline }}
                </a-option>
              </a-select>
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="rule_type" :label="copy.type" required>
              <a-radio-group v-model="form.access_rule.rule_type" type="button">
                <a-radio v-for="type in ruleTypes" :key="type" :value="type">
                  {{ copy.ruleTypes[type] }}
                </a-radio>
              </a-radio-group>
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="username" :label="copy.username" required>
              <a-input
                v-model="form.access_rule.username"
                :max-length="16"
                :placeholder="copy.usernamePlaceholder"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="player_uuid" :label="`${copy.playerUuid} (${copy.optional})`">
              <a-input
                v-model="form.access_rule.player_uuid"
                :placeholder="copy.playerUuidPlaceholder"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="expires_at" :label="`${copy.expiresAt} (${copy.optional})`">
              <a-date-picker
                v-model="form.access_rule.expires_at"
                show-time
                value-format="YYYY-MM-DD HH:mm:ss"
                style="width: 100%"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item :span="{ xs: 1, sm: 1, md: 2, lg: 3 }">
            <a-form-item field="reason" :label="copy.reason" required>
              <a-textarea
                v-model="form.access_rule.reason"
                :max-length="500"
                show-word-limit
                :auto-size="{ minRows: 2, maxRows: 5 }"
                :placeholder="copy.reasonPlaceholder"
              />
            </a-form-item>
          </a-grid-item>
        </a-grid>
        <a-button type="primary" html-type="submit" :loading="form.processing" :disabled="!canSubmit">
          {{ copy.submit }}
        </a-button>
      </a-form>
    </a-card>

    <a-card :title="copy.historyTitle" :bordered="true">
      <a-empty v-if="rules.length === 0" :description="copy.empty" />
      <a-table v-else :data="rules" row-key="id" :pagination="false" :scroll="{ x: 1280 }">
        <template #columns>
          <a-table-column :title="copy.target" :width="220" fixed="left">
            <template #cell="{ record }">
              <a-space direction="vertical" :size="2">
                <a-typography-text bold>{{ record.username }}</a-typography-text>
                <a-typography-text v-if="record.playerUuid" type="secondary" code copyable>
                  {{ record.playerUuid }}
                </a-typography-text>
              </a-space>
            </template>
          </a-table-column>
          <a-table-column :title="copy.server" :width="180">
            <template #cell="{ record }">{{ record.server.name }}</template>
          </a-table-column>
          <a-table-column :title="copy.type" :width="120">
            <template #cell="{ record }">{{ copy.ruleTypes[record.type] }}</template>
          </a-table-column>
          <a-table-column :title="copy.status" :width="150">
            <template #cell="{ record }">
              <a-tag :color="statusColor(record.status)">{{ copy.statuses[record.status] }}</a-tag>
            </template>
          </a-table-column>
          <a-table-column :title="copy.reason" :width="280">
            <template #cell="{ record }">
              <a-typography-paragraph :ellipsis="{ rows: 2, showTooltip: true }">
                {{ record.reason }}
              </a-typography-paragraph>
            </template>
          </a-table-column>
          <a-table-column :title="copy.expiresAt" :width="190">
            <template #cell="{ record }">{{ formatDate(record.expiresAt) }}</template>
          </a-table-column>
          <a-table-column :title="copy.createdBy" :width="160">
            <template #cell="{ record }">{{ record.createdBy || '—' }}</template>
          </a-table-column>
          <a-table-column :title="copy.createdAt" :width="190">
            <template #cell="{ record }">{{ formatDate(record.createdAt) }}</template>
          </a-table-column>
          <a-table-column :title="copy.taskStatus" :width="180">
            <template #cell="{ record }">
              <a-space wrap>
                <a-tag v-if="record.applyTaskStatus">
                  {{ copy.taskStatuses[record.applyTaskStatus] || record.applyTaskStatus }}
                </a-tag>
                <a-tag v-if="record.revokeTaskStatus">
                  {{ copy.taskStatuses[record.revokeTaskStatus] || record.revokeTaskStatus }}
                </a-tag>
              </a-space>
            </template>
          </a-table-column>
          <a-table-column :title="copy.actions" :width="120" fixed="right">
            <template #cell="{ record }">
              <a-button
                v-if="record.canRevoke"
                type="text"
                status="danger"
                @click="openRevoke(record)"
              >
                {{ copy.revoke }}
              </a-button>
              <span v-else>—</span>
            </template>
          </a-table-column>
        </template>
      </a-table>
      <template v-if="paths.next">
        <a-divider />
        <a-row justify="end">
          <a-button @click="router.visit(paths.next)">{{ copy.loadOlder }}</a-button>
        </a-row>
      </template>
    </a-card>

    <a-modal
      :visible="Boolean(revokeRule)"
      :title="copy.revokeTitle"
      :ok-text="copy.revoke"
      :cancel-text="copy.cancel"
      :ok-loading="revoking"
      :ok-button-props="{ status: 'danger', disabled: !revokeReason.trim() }"
      @ok="confirmRevoke"
      @cancel="closeRevoke"
    >
      <a-space direction="vertical" fill>
        <a-alert type="warning" show-icon>
          {{ copy.revokeDescription }}
        </a-alert>
        <a-form-item :label="copy.revokeReason" required>
          <a-textarea
            v-model="revokeReason"
            :max-length="500"
            show-word-limit
            :placeholder="copy.revokeReasonPlaceholder"
          />
        </a-form-item>
      </a-space>
    </a-modal>
  </a-space>
</template>
