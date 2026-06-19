<script setup lang="ts">
import { ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  mappings: Array<{ game_group: string; role_key?: string | null; badge_slug?: string | null }>
  roles: Array<{ key: string; name: string }>
  badges: Array<{ slug: string; name: string }>
  createUrl: string
  backUrl: string
}>()

const { t } = useI18n()

const gameGroup = ref('')
const roleKey = ref('')
const badgeSlug = ref('')

const roleOptions = [{ value: '', label: '—' }, ...props.roles.map((r) => ({ value: r.key, label: r.name }))]
const badgeOptions = [{ value: '', label: '—' }, ...props.badges.map((b) => ({ value: b.slug, label: b.name }))]

function addMapping() {
  if (!gameGroup.value.trim()) return
  router.post(props.createUrl, {
    game_group: gameGroup.value.trim(),
    role_key: roleKey.value || null,
    badge_slug: badgeSlug.value || null,
  })
}

function deleteMapping(index: number) {
  router.delete(`${props.createUrl}/${index}`)
}
</script>

<template>
  <PageHeader :title="t('adminMinecraft.permissionMappings')" />

  <form class="mb-8 max-w-2xl space-y-4 rounded-lg border p-4" @submit.prevent="addMapping">
    <h2 class="text-sm font-medium">{{ t('adminMinecraft.addMapping') }}</h2>
    <div class="grid gap-4 sm:grid-cols-3">
      <div class="space-y-2">
        <Label for="game_group">{{ t('adminMinecraft.gameGroup') }}</Label>
        <Input id="game_group" v-model="gameGroup" placeholder="vip" required />
      </div>
      <div class="space-y-2">
        <Label for="role_key">{{ t('adminMinecraft.websiteRole') }}</Label>
        <Select id="role_key" v-model="roleKey" :options="roleOptions" />
      </div>
      <div class="space-y-2">
        <Label for="badge_slug">{{ t('adminMinecraft.badge') }}</Label>
        <Select id="badge_slug" v-model="badgeSlug" :options="badgeOptions" />
      </div>
    </div>
    <Button type="submit">{{ t('adminMinecraft.addMapping') }}</Button>
  </form>

  <ul v-if="mappings.length" class="max-w-2xl space-y-2">
    <li
      v-for="(mapping, index) in mappings"
      :key="index"
      class="flex flex-wrap items-center justify-between gap-2 rounded-lg border px-3 py-2 text-sm"
    >
      <span>
        <strong>{{ mapping.game_group }}</strong>
        <span v-if="mapping.role_key" class="ml-2 text-muted-foreground">→ {{ mapping.role_key }}</span>
        <span v-if="mapping.badge_slug" class="ml-2 text-muted-foreground">+ {{ mapping.badge_slug }}</span>
      </span>
      <Button type="button" size="sm" variant="destructive" @click="deleteMapping(index)">{{ t('preferences.delete') }}</Button>
    </li>
  </ul>
  <p v-else class="text-sm text-muted-foreground">{{ t('adminMinecraft.noMappings') }}</p>

  <div class="mt-6">
    <Button variant="outline" as-child>
      <a :href="backUrl">{{ t('adminMinecraft.backToServers') }}</a>
    </Button>
  </div>
</template>
