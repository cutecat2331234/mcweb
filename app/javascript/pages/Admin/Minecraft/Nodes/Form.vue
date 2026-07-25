<script setup lang="ts">
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  node: { name: string; hostname: string; status: string; proxy_listen_url: string }
  statusOptions: Array<{ value: string; label: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
  errors?: Record<string, string[]>
}>()

const { t } = useI18n()
const form = useForm({ node: { ...props.node } })

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
  <a-card class="admin-form-card" :bordered="true">
    <a-form :model="form.node" layout="vertical" @submit="submit">
      <a-form-item
        field="name"
        :label="t('adminMinecraft.colName')"
        required
        :validate-status="fieldError('name') ? 'error' : undefined"
        :help="fieldError('name')"
      >
        <a-input v-model="form.node.name" allow-clear />
      </a-form-item>
      <a-form-item
        field="hostname"
        :label="t('adminMinecraft.colHostname')"
        :validate-status="fieldError('hostname') ? 'error' : undefined"
        :help="fieldError('hostname')"
      >
        <a-input v-model="form.node.hostname" allow-clear />
      </a-form-item>
      <a-form-item
        field="proxy_listen_url"
        :label="t('adminMinecraft.proxyListenUrl')"
        :validate-status="fieldError('proxy_listen_url') ? 'error' : undefined"
        :help="fieldError('proxy_listen_url')"
      >
        <a-input v-model="form.node.proxy_listen_url" allow-clear />
      </a-form-item>
      <a-form-item field="status" :label="t('adminMinecraft.colStatus')">
        <a-select v-model="form.node.status" :options="statusOptions" />
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
  max-width: 640px;
}
</style>
