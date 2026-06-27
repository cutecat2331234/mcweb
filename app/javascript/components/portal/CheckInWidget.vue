<script setup lang="ts">
import { computed } from 'vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { CalendarCheck } from '@lucide/vue'
import Button from '@/components/ui/Button.vue'

const { t } = useI18n()
const page = usePage()

const checkIn = computed(
  () => page.props.forum_check_in as { checked_today: boolean; streak: number; url: string } | undefined,
)

function submit() {
  const url = checkIn.value?.url
  if (!url) return
  router.post(url, {}, { preserveScroll: true })
}
</script>

<template>
  <div v-if="checkIn" class="rounded-lg border border-sidebar-border/40 bg-sidebar-accent/20 px-3 py-2 text-xs">
    <div class="mb-1.5 flex items-center gap-1.5 font-medium text-sidebar-foreground">
      <CalendarCheck class="h-3.5 w-3.5 opacity-70" />
      {{ t('checkIn.title') }}
    </div>
    <p class="mb-2 text-sidebar-foreground/70">{{ t('checkIn.streak', { count: checkIn.streak }) }}</p>
    <Button
      v-if="checkIn.checked_today"
      type="button"
      variant="secondary"
      size="sm"
      class="w-full"
      disabled
    >
      {{ t('checkIn.done') }}
    </Button>
    <Button
      v-else
      type="button"
      size="sm"
      class="w-full"
      @click="submit"
    >
      {{ t('checkIn.button') }}
    </Button>
  </div>
</template>
