<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { confirmState, resolveConfirm } from '@/lib/useConfirm'
import Button from '@/components/ui/Button.vue'

const { t } = useI18n()

function cancel() {
  resolveConfirm(false)
}

function accept() {
  resolveConfirm(true)
}
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="opacity-0"
      leave-active-class="transition duration-100 ease-in"
      leave-to-class="opacity-0"
    >
      <div
        v-if="confirmState.open"
        class="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 p-4"
        @click.self="cancel"
      >
        <div
          role="dialog"
          aria-modal="true"
          class="w-full max-w-md rounded-lg border bg-card p-6 shadow-lg"
        >
          <h2 class="text-lg font-semibold">{{ confirmState.options.title }}</h2>
          <p class="mt-2 text-sm text-muted-foreground">{{ confirmState.options.message }}</p>
          <div class="mt-6 flex flex-wrap justify-end gap-2">
            <Button type="button" variant="outline" @click="cancel">
              {{ confirmState.options.cancelLabel || t('common.cancel') }}
            </Button>
            <Button
              type="button"
              :variant="confirmState.options.variant === 'destructive' ? 'destructive' : 'default'"
              @click="accept"
            >
              {{ confirmState.options.confirmLabel || t('common.confirm') }}
            </Button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
