<script setup lang="ts">
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  integrationAction: {
    name: string
    event_key: string
    conditions_json: string
    actions_json: string
    enabled: boolean
    priority: number
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const { t } = useI18n()
const form = useForm({ integration_action: { ...props.integrationAction } })

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" />
  <a-card class="admin-form-card" :bordered="true">
    <a-form :model="form.integration_action" layout="vertical" @submit="submit">
      <a-form-item field="name" :label="t('adminMinecraft.colName')" required>
        <a-input v-model="form.integration_action.name" allow-clear />
      </a-form-item>
      <a-form-item field="event_key" :label="t('adminMinecraft.colEvent')" required>
        <a-input
          v-model="form.integration_action.event_key"
          placeholder="player.join"
          allow-clear
        />
      </a-form-item>
      <a-form-item field="conditions_json" :label="t('adminMinecraft.conditionsJson')">
        <a-textarea
          v-model="form.integration_action.conditions_json"
          class="font-mono"
          :auto-size="{ minRows: 4, maxRows: 16 }"
        />
      </a-form-item>
      <a-form-item field="actions_json" :label="t('adminMinecraft.actionsJson')">
        <a-textarea
          v-model="form.integration_action.actions_json"
          class="font-mono"
          :auto-size="{ minRows: 8, maxRows: 24 }"
        />
      </a-form-item>
      <a-form-item field="priority" :label="t('adminMinecraft.colPriority')">
        <a-input-number v-model="form.integration_action.priority" :precision="0" />
      </a-form-item>
      <a-form-item field="enabled" :label="t('adminMinecraft.colEnabled')">
        <a-switch v-model="form.integration_action.enabled" />
      </a-form-item>
      <a-space>
        <a-button html-type="submit" type="primary" :loading="form.processing">
          {{ t('common.save') }}
        </a-button>
        <a-button @click="router.visit(backUrl)">{{ t('common.cancel') }}</a-button>
      </a-space>
    </a-form>
  </a-card>
</template>

<style scoped>
.admin-form-card {
  max-width: 760px;
}
</style>
