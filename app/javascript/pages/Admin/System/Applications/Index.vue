<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

interface CatalogItem {
  id: string
  label: string
  description: string
  always_on?: boolean
  enabled?: boolean
  ruby_namespaces?: string[]
  admin_module_key?: string
  path_prefixes?: string[]
  kind?: string
  host?: string
  capabilities?: string[]
  limitations?: string[]
}

defineProps<{
  title: string
  platform: CatalogItem[]
  applications: CatalogItem[]
  extensions: CatalogItem[]
  freelyExtensible: boolean
  featureFlagsUrl: string
}>()
</script>

<template>
  <PageHeader :title="title" :subtitle="t('admin.applications.subtitle')" />

  <div v-if="!freelyExtensible" class="mb-6 max-w-3xl rounded-lg border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-950 dark:text-amber-100">
    {{ t('admin.applications.notFreelyExtensible') }}
    <span class="ml-1 text-muted-foreground">{{ t('admin.applications.readDocs') }}</span>
  </div>

  <section class="mb-8">
    <h2 class="mb-3 text-lg font-semibold">{{ t('admin.applications.platformTitle') }}</h2>
    <p class="mb-4 text-sm text-muted-foreground">{{ t('admin.applications.platformHint') }}</p>
    <div class="grid gap-3 md:grid-cols-2">
      <div
        v-for="item in platform"
        :key="item.id"
        class="rounded-lg border border-border bg-card p-4"
      >
        <div class="mb-1 flex items-center gap-2">
          <span class="font-medium">{{ item.label }}</span>
          <Badge variant="secondary">{{ t('admin.applications.tierPlatform') }}</Badge>
        </div>
        <p class="text-sm text-muted-foreground">{{ item.description }}</p>
        <p v-if="item.ruby_namespaces?.length" class="mt-2 font-mono text-xs text-muted-foreground">
          {{ item.ruby_namespaces.join(' · ') }}
        </p>
      </div>
    </div>
  </section>

  <section class="mb-8">
    <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
      <div>
        <h2 class="text-lg font-semibold">{{ t('admin.applications.appsTitle') }}</h2>
        <p class="text-sm text-muted-foreground">{{ t('admin.applications.appsHint') }}</p>
      </div>
      <Button as-child variant="outline" size="sm">
        <Link :href="featureFlagsUrl">{{ t('admin.applications.manageToggles') }}</Link>
      </Button>
    </div>
    <div class="grid gap-3 md:grid-cols-2">
      <div
        v-for="item in applications"
        :key="item.id"
        class="rounded-lg border border-border bg-card p-4"
      >
        <div class="mb-1 flex flex-wrap items-center gap-2">
          <span class="font-medium">{{ item.label }}</span>
          <Badge :variant="item.enabled ? 'default' : 'secondary'">
            {{ item.enabled ? t('admin.ui.enabled') : t('admin.ui.disabled') }}
          </Badge>
          <Badge variant="outline">{{ t('admin.applications.tierApplication') }}</Badge>
        </div>
        <p class="text-sm text-muted-foreground">{{ item.description }}</p>
        <p v-if="item.ruby_namespaces?.length" class="mt-2 font-mono text-xs text-muted-foreground">
          {{ item.ruby_namespaces.join(' · ') }}
        </p>
        <p v-if="item.path_prefixes?.length" class="mt-1 font-mono text-xs text-muted-foreground">
          {{ item.path_prefixes.join(', ') }}
        </p>
      </div>
    </div>
  </section>

  <section>
    <h2 class="mb-3 text-lg font-semibold">{{ t('admin.applications.extensionsTitle') }}</h2>
    <p class="mb-4 text-sm text-muted-foreground">{{ t('admin.applications.extensionsHint') }}</p>
    <div class="grid gap-3">
      <div
        v-for="item in extensions"
        :key="item.id"
        class="rounded-lg border border-border bg-card p-4"
      >
        <div class="mb-1 flex flex-wrap items-center gap-2">
          <span class="font-medium">{{ item.label }}</span>
          <Badge variant="outline">{{ t('admin.applications.tierExtension') }}</Badge>
          <span v-if="item.kind" class="text-xs text-muted-foreground">{{ item.kind }}</span>
        </div>
        <p class="text-sm text-muted-foreground">{{ item.description }}</p>
        <p v-if="item.host" class="mt-2 font-mono text-xs text-muted-foreground">{{ item.host }}</p>
        <ul v-if="item.limitations?.length" class="mt-2 list-inside list-disc text-xs text-muted-foreground">
          <li v-for="(line, idx) in item.limitations" :key="idx">{{ line }}</li>
        </ul>
      </div>
    </div>
  </section>
</template>
