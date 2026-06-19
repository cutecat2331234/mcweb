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
  server: { name: string; address: string; port: number; status: string }
  statusOptions: Array<{ value: string; label: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
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
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('common.save') }}</Button>
      <Button type="button" variant="outline" as-child>
        <a :href="backUrl">{{ t('common.cancel') }}</a>
      </Button>
    </div>
  </form>
</template>
