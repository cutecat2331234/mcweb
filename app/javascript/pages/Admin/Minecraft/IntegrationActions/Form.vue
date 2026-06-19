<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

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
  <PageHeader :title="title" />
  <form class="max-w-2xl space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">{{ t('adminMinecraft.colName') }}</Label>
      <Input id="name" v-model="form.integration_action.name" required />
    </div>
    <div class="space-y-2">
      <Label for="event_key">{{ t('adminMinecraft.colEvent') }}</Label>
      <Input id="event_key" v-model="form.integration_action.event_key" placeholder="player.join" required />
    </div>
    <div class="space-y-2">
      <Label for="conditions_json">{{ t('adminMinecraft.conditionsJson') }}</Label>
      <Textarea id="conditions_json" v-model="form.integration_action.conditions_json" rows="4" class="font-mono text-sm" />
    </div>
    <div class="space-y-2">
      <Label for="actions_json">{{ t('adminMinecraft.actionsJson') }}</Label>
      <Textarea id="actions_json" v-model="form.integration_action.actions_json" rows="8" class="font-mono text-sm" />
    </div>
    <div class="space-y-2">
      <Label for="priority">{{ t('adminMinecraft.colPriority') }}</Label>
      <Input id="priority" v-model.number="form.integration_action.priority" type="number" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.integration_action.enabled" />
      {{ t('adminMinecraft.colEnabled') }}
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('common.save') }}</Button>
      <Button type="button" variant="outline" as-child>
        <a :href="backUrl">{{ t('common.cancel') }}</a>
      </Button>
    </div>
  </form>
</template>
