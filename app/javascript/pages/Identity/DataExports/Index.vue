<script setup lang="ts">
import { computed } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Alert from '@/components/ui/Alert.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

type DataExport = {
  id: string
  status: 'queued' | 'running' | 'completed' | 'failed' | 'revoked' | 'expired'
  requested_at?: string | null
  started_at?: string | null
  completed_at?: string | null
  expires_at?: string | null
  attempts: number
  error_code?: string | null
  downloadable: boolean
  manifest: Record<string, number>
  paths: {
    download: string
    retry: string
    revoke: string
  }
}

const props = defineProps<{
  exports: DataExport[]
  retention_hours: number
  daily_limit: number
}>()

const { t, locale } = useI18n()
const activeExport = computed(() => props.exports.find((item) => ['queued', 'running'].includes(item.status)))

function formatDate(value?: string | null) {
  if (!value) return t('common.notAvailable')
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

function requestExport() {
  router.post(
    routes.identityDataExports,
    { data_export: { idempotency_key: crypto.randomUUID() } },
    { preserveScroll: true },
  )
}

function retryExport(item: DataExport) {
  router.post(item.paths.retry, {}, { preserveScroll: true })
}

function revokeExport(item: DataExport) {
  if (!window.confirm(t('identity.dataExports.revokeConfirm'))) return
  router.delete(item.paths.revoke, { preserveScroll: true })
}

function badgeVariant(status: DataExport['status']): 'success' | 'danger' | 'default' | 'secondary' {
  if (status === 'completed') return 'success'
  if (status === 'failed' || status === 'revoked') return 'danger'
  if (status === 'running') return 'default'
  return 'secondary'
}
</script>

<template>
  <PageHeader
    :title="t('identity.dataExports.title')"
    :subtitle="t('identity.dataExports.subtitle')"
  >
    <template #actions>
      <Button type="button" :disabled="Boolean(activeExport)" @click="requestExport">
        {{ t('identity.dataExports.request') }}
      </Button>
    </template>
  </PageHeader>

  <div class="max-w-4xl space-y-5">
    <Alert :title="t('identity.dataExports.privacyTitle')">
      {{
        t('identity.dataExports.privacyDescription', {
          hours: retention_hours,
          limit: daily_limit,
        })
      }}
    </Alert>

    <section
      v-if="exports.length === 0"
      class="rounded-2xl border border-dashed bg-card p-10 text-center shadow-sm"
    >
      <h2 class="text-lg font-semibold">{{ t('identity.dataExports.emptyTitle') }}</h2>
      <p class="mt-2 text-sm text-muted-foreground">{{ t('identity.dataExports.emptyDescription') }}</p>
    </section>

    <ol v-else class="space-y-4" :aria-label="t('identity.dataExports.history')">
      <li
        v-for="item in exports"
        :key="item.id"
        class="rounded-2xl border bg-card p-5 shadow-sm"
      >
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0 space-y-2">
            <div class="flex flex-wrap items-center gap-2">
              <h2 class="font-semibold">{{ t('identity.dataExports.exportLabel') }}</h2>
              <Badge :variant="badgeVariant(item.status)">
                {{ t(`identity.dataExports.status.${item.status}`) }}
              </Badge>
            </div>
            <dl class="grid gap-x-6 gap-y-1 text-sm text-muted-foreground sm:grid-cols-2">
              <div>
                <dt class="inline font-medium text-foreground">{{ t('identity.dataExports.requestedAt') }}:</dt>
                <dd class="ml-1 inline">{{ formatDate(item.requested_at) }}</dd>
              </div>
              <div>
                <dt class="inline font-medium text-foreground">{{ t('identity.dataExports.expiresAt') }}:</dt>
                <dd class="ml-1 inline">{{ formatDate(item.expires_at) }}</dd>
              </div>
              <div>
                <dt class="inline font-medium text-foreground">{{ t('identity.dataExports.attempts') }}:</dt>
                <dd class="ml-1 inline">{{ item.attempts }}</dd>
              </div>
            </dl>
            <p v-if="item.error_code" role="alert" class="text-sm text-destructive">
              {{ t('identity.dataExports.failedDescription') }}
            </p>
          </div>

          <div class="flex flex-wrap gap-2">
            <Button v-if="item.downloadable" as-child>
              <a :href="item.paths.download">{{ t('identity.dataExports.download') }}</a>
            </Button>
            <Button
              v-if="item.status === 'failed' || item.status === 'expired'"
              type="button"
              variant="outline"
              @click="retryExport(item)"
            >
              {{ t('identity.dataExports.retry') }}
            </Button>
            <Button
              v-if="!['revoked', 'expired'].includes(item.status)"
              type="button"
              variant="outline"
              @click="revokeExport(item)"
            >
              {{ t('identity.dataExports.revoke') }}
            </Button>
          </div>
        </div>
      </li>
    </ol>

    <Button as-child variant="ghost">
      <Link :href="routes.security">{{ t('identity.dataExports.backToSecurity') }}</Link>
    </Button>
  </div>
</template>
