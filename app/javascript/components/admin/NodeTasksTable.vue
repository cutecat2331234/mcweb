<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import Button from '@/components/ui/Button.vue'

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
const expanded = ref<Record<number, boolean>>({})

function toggle(id: number) {
  expanded.value[id] = !expanded.value[id]
}

function hasResult(task: NodeTaskRow): boolean {
  const r = task.result
  if (!r) return false
  return !!(r.stdout || r.stderr || r.output || r.error || r.message)
}

function resultText(task: NodeTaskRow): string {
  const r = task.result || {}
  const parts: string[] = []
  if (r.message) parts.push(r.message)
  if (r.error) parts.push(`Error: ${r.error}`)
  if (r.stdout) parts.push(`stdout:\n${r.stdout}`)
  if (r.stderr) parts.push(`stderr:\n${r.stderr}`)
  if (r.output) parts.push(r.output)
  return parts.join('\n\n') || '—'
}

function payloadHint(task: NodeTaskRow): string {
  const p = task.payload
  if (!p) return '—'
  if (p.command) return p.command
  if (p.path) return p.path
  return '—'
}

function statusClass(status: string): string {
  if (status === 'completed') return 'text-green-700 dark:text-green-400'
  if (status === 'failed') return 'text-red-700 dark:text-red-400'
  if (status === 'pending' || status === 'claimed') return 'text-amber-700 dark:text-amber-400'
  return ''
}
</script>

<template>
  <section class="mt-8">
    <h2 class="mb-3 text-lg font-semibold">{{ t('adminMinecraft.nodeTasks') }}</h2>
    <div class="overflow-x-auto rounded-md border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{{ t('adminMinecraft.colType') }}</TableHead>
            <TableHead>{{ t('adminMinecraft.colStatus') }}</TableHead>
            <TableHead>{{ t('adminMinecraft.taskDetail') }}</TableHead>
            <TableHead>{{ t('adminMinecraft.completedAt') }}</TableHead>
            <TableHead class="w-24" />
          </TableRow>
        </TableHeader>
        <TableBody>
          <template v-for="task in props.tasks" :key="task.id">
            <TableRow>
              <TableCell class="font-mono text-xs">{{ task.task_type }}</TableCell>
              <TableCell :class="statusClass(task.status)">{{ task.status }}</TableCell>
              <TableCell class="max-w-xs truncate font-mono text-xs">{{ payloadHint(task) }}</TableCell>
              <TableCell class="text-xs text-muted-foreground">{{ task.completed_at || '—' }}</TableCell>
              <TableCell>
                <Button
                  v-if="hasResult(task)"
                  type="button"
                  variant="ghost"
                  size="sm"
                  @click="toggle(task.id)"
                >
                  {{ expanded[task.id] ? t('adminMinecraft.hideResult') : t('adminMinecraft.showResult') }}
                </Button>
              </TableCell>
            </TableRow>
            <TableRow v-if="expanded[task.id]">
              <TableCell colspan="5" class="bg-muted/40 p-0">
                <pre class="max-h-80 overflow-auto p-3 text-xs whitespace-pre-wrap">{{ resultText(task) }}</pre>
              </TableCell>
            </TableRow>
          </template>
          <TableRow v-if="!props.tasks.length">
            <TableCell colspan="5" class="text-muted-foreground">{{ t('adminMinecraft.noNodeTasks') }}</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>
  </section>
</template>
