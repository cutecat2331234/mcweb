<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Textarea from '@/components/ui/Textarea.vue'

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

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <PageHeader :title="title" />
  <p v-if="suggestedNode" class="mb-4 text-sm text-muted-foreground">{{ t('adminMinecraft.suggestedNode', { name: suggestedNode }) }}</p>
  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">{{ t('adminMinecraft.colName') }}</Label>
      <Input id="name" v-model="form.server.name" required />
    </div>
    <div class="space-y-2">
      <Label for="address">{{ t('adminMinecraft.colAddress') }}</Label>
      <Input id="address" v-model="form.server.address" />
    </div>
    <div class="space-y-2">
      <Label for="port">{{ t('adminMinecraft.colPort') }}</Label>
      <Input id="port" v-model.number="form.server.port" type="number" min="1" max="65535" />
    </div>
    <div class="space-y-2">
      <Label for="status">{{ t('adminMinecraft.colStatus') }}</Label>
      <Select id="status" v-model="form.server.status" :options="statusOptions" />
    </div>
    <div class="space-y-2">
      <Label for="minecraft_node_id">{{ t('adminMinecraft.node') }}</Label>
      <Select id="minecraft_node_id" v-model="form.server.minecraft_node_id" :options="[{ value: '', label: '—' }, ...nodeOptions]" />
    </div>
    <div class="space-y-2">
      <Label for="connection_mode">{{ t('adminMinecraft.connectionMode') }}</Label>
      <Select id="connection_mode" v-model="form.server.connection_mode" :options="connectionModeOptions" />
    </div>
    <div class="space-y-2">
      <Label for="proxy_listen_url">{{ t('adminMinecraft.proxyListenUrl') }}</Label>
      <Input id="proxy_listen_url" v-model="form.server.proxy_listen_url" :placeholder="t('adminMinecraft.proxyListenPlaceholder')" />
    </div>
    <div class="space-y-2">
      <Label for="process_driver">{{ t('adminMinecraft.processDriver') }}</Label>
      <Select id="process_driver" v-model="form.server.process_driver" :options="[{ value: '', label: '—' }, ...processDriverOptions]" />
    </div>
    <div class="space-y-2">
      <Label for="working_directory">{{ t('adminMinecraft.workingDirectory') }}</Label>
      <Input id="working_directory" v-model="form.server.working_directory" />
    </div>
    <div class="space-y-2">
      <Label for="process_config">{{ t('adminMinecraft.processConfig') }}</Label>
      <Textarea id="process_config" v-model="form.server.process_config" rows="6" placeholder='{"unit":"mc.service"}' />
    </div>

    <h2 class="pt-2 font-semibold">{{ t('adminMinecraft.gracefulStopSection') }}</h2>
    <div class="space-y-2">
      <Label for="graceful_stop_enabled">{{ t('adminMinecraft.gracefulStopEnabled') }}</Label>
      <Input id="graceful_stop_enabled" v-model="form.server.graceful_stop_enabled" placeholder="true / false / empty=inherit" />
    </div>
    <div class="space-y-2">
      <Label for="graceful_stop_countdown">{{ t('adminMinecraft.gracefulStopCountdown') }}</Label>
      <Input id="graceful_stop_countdown" v-model="form.server.graceful_stop_countdown" type="number" />
    </div>
    <div class="space-y-2">
      <Label for="graceful_stop_message">{{ t('adminMinecraft.gracefulStopMessage') }}</Label>
      <Input id="graceful_stop_message" v-model="form.server.graceful_stop_message" />
    </div>
    <div class="space-y-2">
      <Label for="graceful_stop_commands">{{ t('adminMinecraft.gracefulStopCommands') }}</Label>
      <Input id="graceful_stop_commands" v-model="form.server.graceful_stop_commands" />
    </div>

    <h2 class="pt-2 font-semibold">{{ t('adminMinecraft.schedulesSection') }}</h2>
    <div class="space-y-2">
      <Label for="restart_schedule">{{ t('adminMinecraft.restartSchedule') }}</Label>
      <Input id="restart_schedule" v-model="form.server.restart_schedule" placeholder="0 4 * * *" />
    </div>
    <div class="space-y-2">
      <Label for="backup_enabled">{{ t('adminMinecraft.backupEnabled') }}</Label>
      <Input id="backup_enabled" v-model="form.server.backup_enabled" placeholder="true / false" />
    </div>
    <div class="space-y-2">
      <Label for="backup_schedule">{{ t('adminMinecraft.backupSchedule') }}</Label>
      <Input id="backup_schedule" v-model="form.server.backup_schedule" />
    </div>
    <div class="space-y-2">
      <Label for="world_directory">{{ t('adminMinecraft.worldDirectory') }}</Label>
      <Input id="world_directory" v-model="form.server.world_directory" />
    </div>

    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('common.save') }}</Button>
      <Button type="button" variant="outline" as-child>
        <a :href="backUrl">{{ t('common.cancel') }}</a>
      </Button>
    </div>
  </form>
</template>
