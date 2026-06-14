<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Label from '@/components/ui/Label.vue'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  reportableType: string
  reportableId: string
  reasonOptions: Array<{ value: string; label: string }>
}>()

const form = useForm({
  report: {
    reportable_type: props.reportableType,
    reportable_id: props.reportableId,
    reason_code: 'spam',
    reason_detail: '',
  },
})

function submit() {
  form.post('/forum/reports')
}
</script>

<template>
  <PageHeader title="举报内容" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="reason_code">举报类型</Label>
      <select
        id="reason_code"
        v-model="form.report.reason_code"
        required
        class="h-9 w-full rounded-md border border-input bg-transparent px-3 text-sm"
      >
        <option v-for="opt in reasonOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
    </div>
    <div class="space-y-2">
      <Label for="reason_detail">补充说明（可选）</Label>
      <Textarea id="reason_detail" v-model="form.report.reason_detail" rows="4" placeholder="请描述具体问题…" />
    </div>
    <div class="flex gap-3">
      <Button type="submit" :disabled="form.processing">提交举报</Button>
      <Button as-child variant="outline">
        <Link href="/" preserve-state>取消</Link>
      </Button>
    </div>
  </form>
</template>
