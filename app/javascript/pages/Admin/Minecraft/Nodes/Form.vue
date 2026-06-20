<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'

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

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <PageHeader :title="title" />
  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">{{ t('adminMinecraft.colName') }}</Label>
      <Input id="name" v-model="form.node.name" required />
    </div>
    <div class="space-y-2">
      <Label for="hostname">{{ t('adminMinecraft.colHostname') }}</Label>
      <Input id="hostname" v-model="form.node.hostname" />
    </div>
    <div class="space-y-2">
      <Label for="proxy_listen_url">{{ t('adminMinecraft.proxyListenUrl') }}</Label>
      <Input id="proxy_listen_url" v-model="form.node.proxy_listen_url" />
    </div>
    <div class="space-y-2">
      <Label for="status">{{ t('adminMinecraft.colStatus') }}</Label>
      <Select id="status" v-model="form.node.status" :options="statusOptions" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('common.save') }}</Button>
      <Button type="button" variant="outline" as-child>
        <a :href="backUrl">{{ t('common.cancel') }}</a>
      </Button>
    </div>
  </form>
</template>
