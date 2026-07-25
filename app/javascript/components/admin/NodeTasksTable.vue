<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'

export interface NodeTaskRow {
  id: number
  task_type: string
  status: string
  completed_at: string | null
  result?: {
    stdout?: string
    stderr?: string
    output?: string
    error?: string
    message?: string
    success?: boolean
  }
  payload?: {
    command?: string
    path?: string
    lines?: number
  }
}

const props = defineProps<{
  tasks: NodeTaskRow[]
}>()

const { t } = useI18n()
const resultTask = ref<NodeTaskRow | null>(null)
const resultVisible = computed({
  get: () => resultTask.value !== null,
  set: (visible: boolean) => {
    if (!visible) resultTask.value = null
  },
})

function hasResult(task: NodeTaskRow): boolean {
  const result = task.result
  if (!result) return false
  return Boolean(result.stdout || result.stderr || result.output || result.error || result.message)
}

function resultText(task: NodeTaskRow): string {
  const result = task.result || {}
  const parts: string[] = []
  if (result.message) parts.push(result.message)
  if (result.error) parts.push(`Error: ${result.error}`)
  if (result.stdout) parts.push(`stdout:\n${result.stdout}`)
  if (result.stderr) parts.push(`stderr:\n${result.stderr}`)
  if (result.output) parts.push(result.output)
  return parts.join('\n\n') || '—'
}

function payloadHint(task: NodeTaskRow): string {
  const payload = task.payload
  if (!payload) return '—'
  if (payload.command) return payload.command
  if (payload.path) return payload.path
  return '—'
}

function statusColor(status: string): string {
  if (status === 'completed') return 'green'
  if (status === 'failed') return 'red'
  if (status === 'pending' || status === 'claimed') return 'orangered'
  return 'gray'
}

const columns = computed(() => [
  { title: t('adminMinecraft.colType'), dataIndex: 'task_type', slotName: 'taskType' },
  { title: t('adminMinecraft.colStatus'), dataIndex: 'status', slotName: 'status', width: 120 },
  { title: t('adminMinecraft.taskDetail'), dataIndex: 'payload', slotName: 'detail' },
  {
    title: t('adminMinecraft.completedAt'),
    dataIndex: 'completed_at',
    slotName: 'completedAt',
    width: 180,
  },
  { title: '', slotName: 'actions', width: 120 },
])
</script>

<template>
  <a-card class="mt-8" :title="t('adminMinecraft.nodeTasks')" :bordered="true">
    <a-table
      :columns="columns"
      :data="props.tasks"
      row-key="id"
      :pagination="false"
      :scroll="{ x: 760 }"
    >
      <template #taskType="{ record }">
        <a-typography-text code>{{ record.task_type }}</a-typography-text>
      </template>
      <template #status="{ record }">
        <a-tag :color="statusColor(record.status)">{{ record.status }}</a-tag>
      </template>
      <template #detail="{ record }">
        <a-typography-text :ellipsis="{ showTooltip: true }">
          {{ payloadHint(record) }}
        </a-typography-text>
      </template>
      <template #completedAt="{ record }">
        {{ record.completed_at || '—' }}
      </template>
      <template #actions="{ record }">
        <a-button
          v-if="hasResult(record)"
          type="text"
          size="small"
          @click="resultTask = record"
        >
          {{ t('adminMinecraft.showResult') }}
        </a-button>
      </template>
      <template #empty>
        <a-empty :description="t('adminMinecraft.noNodeTasks')" />
      </template>
    </a-table>
  </a-card>

  <a-modal
    v-model:visible="resultVisible"
    :title="t('adminMinecraft.taskDetail')"
    :footer="false"
    :width="'min(720px, calc(100vw - 32px))'"
  >
    <pre class="node-task-result">{{ resultTask ? resultText(resultTask) : '' }}</pre>
  </a-modal>
</template>

<style scoped>
.node-task-result {
  max-height: 60vh;
  margin: 0;
  padding: 12px;
  overflow: auto;
  color: var(--color-text-1);
  background: var(--color-fill-2);
  border-radius: 4px;
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
