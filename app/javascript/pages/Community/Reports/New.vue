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
}>()

const form = useForm({
  report: {
    reportable_type: props.reportableType,
    reportable_id: props.reportableId,
    reason: '',
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
      <Label for="reason">原因</Label>
      <Textarea id="reason" v-model="form.report.reason" required rows="4" />
    </div>
    <div class="flex gap-3">
      <Button type="submit" :disabled="form.processing">提交举报</Button>
      <Button as-child variant="outline">
        <Link href="/" preserve-state>取消</Link>
      </Button>
    </div>
  </form>
</template>
