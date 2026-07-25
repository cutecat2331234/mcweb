<script setup lang="ts">
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  server: Record<string, string | number>
  statusOptions: Array<{ value: string; label: string }>
  connectionModeOptions: Array<{ value: string; label: string }>
  processDriverOptions: Array<{ value: string; label: string }>
  nodeOptions: Array<{ value: string; label: string }>
  suggestedNode?: string | null
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
  errors?: Record<string, string[]>
}>()

const { t } = useI18n()
const form = useForm({ server: { ...props.server } })
const optionalNodeOptions = [{ value: '', label: '—' }, ...props.nodeOptions]
const optionalProcessDriverOptions = [{ value: '', label: '—' }, ...props.processDriverOptions]
const inheritBooleanOptions = [
  { value: '', label: '—' },
  { value: 'true', label: t('adminMinecraft.yes') },
  { value: 'false', label: t('adminMinecraft.no') },
]

function fieldError(key: string) {
  return props.errors?.[key]?.join(' ') || ''
}

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" />
  <a-alert v-if="suggestedNode" type="info" show-icon class="mb-4">
    {{ t('adminMinecraft.suggestedNode', { name: suggestedNode }) }}
  </a-alert>

  <a-form :model="form.server" layout="vertical" class="admin-server-form" @submit="submit">
    <a-space direction="vertical" fill>
      <a-card :bordered="true">
        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
          <a-grid-item>
            <a-form-item
              field="name"
              :label="t('adminMinecraft.colName')"
              required
              :validate-status="fieldError('name') ? 'error' : undefined"
              :help="fieldError('name')"
            >
              <a-input v-model="form.server.name" allow-clear />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="status" :label="t('adminMinecraft.colStatus')">
              <a-select v-model="form.server.status" :options="statusOptions" />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="address"
              :label="t('adminMinecraft.colAddress')"
              :validate-status="fieldError('address') ? 'error' : undefined"
              :help="fieldError('address')"
            >
              <a-input v-model="form.server.address" allow-clear />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="port"
              :label="t('adminMinecraft.colPort')"
              :validate-status="fieldError('port') ? 'error' : undefined"
              :help="fieldError('port')"
            >
              <a-input v-model.number="form.server.port" type="number" min="1" max="65535" />
            </a-form-item>
          </a-grid-item>
        </a-grid>
      </a-card>

      <a-card :title="t('adminMinecraft.node')" :bordered="true">
        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
          <a-grid-item>
            <a-form-item field="minecraft_node_id" :label="t('adminMinecraft.node')">
              <a-select
                v-model="form.server.minecraft_node_id"
                :options="optionalNodeOptions"
                allow-search
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="connection_mode"
              :label="t('adminMinecraft.connectionMode')"
            >
              <a-select
                v-model="form.server.connection_mode"
                :options="connectionModeOptions"
              />
            </a-form-item>
          </a-grid-item>
        </a-grid>
        <a-form-item field="proxy_listen_url" :label="t('adminMinecraft.proxyListenUrl')">
          <a-input
            v-model="form.server.proxy_listen_url"
            :placeholder="t('adminMinecraft.proxyListenPlaceholder')"
            allow-clear
          />
        </a-form-item>
        <a-form-item field="process_driver" :label="t('adminMinecraft.processDriver')">
          <a-select
            v-model="form.server.process_driver"
            :options="optionalProcessDriverOptions"
          />
        </a-form-item>
        <a-form-item field="working_directory" :label="t('adminMinecraft.workingDirectory')">
          <a-input v-model="form.server.working_directory" allow-clear />
        </a-form-item>
        <a-form-item field="process_config" :label="t('adminMinecraft.processConfig')">
          <a-textarea
            v-model="form.server.process_config"
            class="font-mono"
            placeholder='{"unit":"mc.service"}'
            :auto-size="{ minRows: 6, maxRows: 18 }"
          />
        </a-form-item>
      </a-card>

      <a-card :title="t('adminMinecraft.gracefulStopSection')" :bordered="true">
        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
          <a-grid-item>
            <a-form-item
              field="graceful_stop_enabled"
              :label="t('adminMinecraft.gracefulStopEnabled')"
            >
              <a-select
                v-model="form.server.graceful_stop_enabled"
                :options="inheritBooleanOptions"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="graceful_stop_countdown"
              :label="t('adminMinecraft.gracefulStopCountdown')"
            >
              <a-input
                v-model.number="form.server.graceful_stop_countdown"
                type="number"
                min="0"
              />
            </a-form-item>
          </a-grid-item>
        </a-grid>
        <a-form-item
          field="graceful_stop_message"
          :label="t('adminMinecraft.gracefulStopMessage')"
        >
          <a-input v-model="form.server.graceful_stop_message" allow-clear />
        </a-form-item>
        <a-form-item
          field="graceful_stop_commands"
          :label="t('adminMinecraft.gracefulStopCommands')"
        >
          <a-input v-model="form.server.graceful_stop_commands" allow-clear />
        </a-form-item>
      </a-card>

      <a-card :title="t('adminMinecraft.schedulesSection')" :bordered="true">
        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
          <a-grid-item>
            <a-form-item
              field="restart_schedule"
              :label="t('adminMinecraft.restartSchedule')"
            >
              <a-input v-model="form.server.restart_schedule" placeholder="0 4 * * *" allow-clear />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="backup_enabled" :label="t('adminMinecraft.backupEnabled')">
              <a-select
                v-model="form.server.backup_enabled"
                :options="inheritBooleanOptions.slice(1)"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="backup_schedule" :label="t('adminMinecraft.backupSchedule')">
              <a-input v-model="form.server.backup_schedule" allow-clear />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="world_directory" :label="t('adminMinecraft.worldDirectory')">
              <a-input v-model="form.server.world_directory" allow-clear />
            </a-form-item>
          </a-grid-item>
        </a-grid>
      </a-card>

      <a-space>
        <a-button html-type="submit" type="primary" :loading="form.processing">
          {{ t('common.save') }}
        </a-button>
        <a-button @click="router.visit(backUrl)">{{ t('common.cancel') }}</a-button>
      </a-space>
    </a-space>
  </a-form>
</template>

<style scoped>
.admin-server-form {
  max-width: 880px;
}
</style>
