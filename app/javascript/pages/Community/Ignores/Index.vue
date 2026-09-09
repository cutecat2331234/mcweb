<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'
import type { CommunityRelationshipSnapshot } from '@/lib/communityRelationshipMutation'
import { useCommunityRelationshipList } from '@/lib/useCommunityRelationship'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  users: Array<{
    username: string
    display_name: string | null
    profile_url: string
    ignored_at: string
    unignore_url: string
    relationship: CommunityRelationshipSnapshot
  }>
}>()

const { states, visibleUsers, remove } = useCommunityRelationshipList(() => props.users)
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.ignores.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.ignores.title')" />

  <div v-if="visibleUsers.length" class="divide-y rounded-lg border">
    <div v-for="user in visibleUsers" :key="user.username" class="flex items-center justify-between gap-4 p-4">
      <div>
        <Link :href="user.profile_url" class="font-medium hover:underline">{{ user.display_name || user.username }}</Link>
        <p class="text-xs text-muted-foreground">{{ t('forum.ignores.ignoredAt', { at: user.ignored_at }) }}</p>
        <p v-if="states.get(user.username)?.error" role="status" class="text-sm text-muted-foreground">{{ t(`components.relationship.errors.${states.get(user.username)?.error}`) }}</p>
      </div>
      <Button type="button" variant="outline" size="sm" :disabled="states.get(user.username)?.processing || !states.get(user.username)?.revision" @click="remove(user, user.unignore_url)">{{ states.get(user.username)?.error === 'retry' ? t('components.relationship.retry') : t('forum.ignores.unignore') }}</Button>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('forum.ignores.empty') }}</p>
</template>
