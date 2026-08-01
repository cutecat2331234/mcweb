<script setup lang="ts">
import { ref, watch } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Alert from '@/components/ui/Alert.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  email: string
  email_verified: boolean
  totp_enabled: boolean
  require_totp: boolean
  recovery_codes_remaining: number
  new_recovery_codes?: string[] | null
  pending_totp?: {
    secret: string
    provisioning_uri: string
    qr_svg: string
  } | null
}>()

const { t } = useI18n()
const recoveryCodesVisible = ref(Boolean(props.new_recovery_codes?.length))
const recoveryCodesAcknowledged = ref(false)
const recoveryCodesFeedback = ref('')

watch(
  () => props.new_recovery_codes,
  (codes) => {
    recoveryCodesVisible.value = Boolean(codes?.length)
    recoveryCodesAcknowledged.value = false
    recoveryCodesFeedback.value = ''
  },
)

const confirmForm = useForm({
  totp: { code: '' },
})

const disableForm = useForm({
  totp: { password: '', code: '' },
})

const recoveryCodesForm = useForm({
  recovery_codes: { password: '', code: '' },
})

const emailForm = useForm({
  email_change: { email: props.email, password: '', code: '' },
})

const accountCloseForm = useForm({
  account_close: {
    password: '',
    code: '',
    confirmation: '',
    closure_mode: 'anonymize',
    reason: '',
  },
})

function startSetup() {
  router.post(routes.securityTotpSetup, {}, { preserveScroll: true })
}

function confirmTotp() {
  confirmForm.post(routes.securityTotpConfirm, { preserveScroll: true })
}

function disableTotp() {
  disableForm.post(routes.securityTotpDisable, {
    preserveScroll: true,
    onSuccess: () => disableForm.reset(),
  })
}

function regenerateRecoveryCodes() {
  recoveryCodesForm.post(routes.securityRecoveryCodes, {
    preserveScroll: true,
    onSuccess: () => recoveryCodesForm.reset(),
  })
}

function changeEmail() {
  emailForm.patch(routes.securityEmail, {
    preserveScroll: true,
    onSuccess: () => {
      emailForm.email_change.password = ''
      emailForm.email_change.code = ''
    },
  })
}

function closeAccount() {
  accountCloseForm.delete(routes.securityAccount, { preserveScroll: true })
}

function recoveryCodesText() {
  return (props.new_recovery_codes || []).join('\n')
}

async function copyRecoveryCodes() {
  try {
    await navigator.clipboard.writeText(recoveryCodesText())
    recoveryCodesFeedback.value = t('identity.security.recoveryCodesCopied')
  } catch {
    recoveryCodesFeedback.value = t('identity.security.recoveryCodesCopyFailed')
  }
}

function downloadRecoveryCodes() {
  const blob = new Blob([`${recoveryCodesText()}\n`], { type: 'text/plain;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = 'mcweb-recovery-codes.txt'
  link.click()
  URL.revokeObjectURL(url)
  recoveryCodesFeedback.value = t('identity.security.recoveryCodesDownloaded')
}

function dismissRecoveryCodes() {
  if (!recoveryCodesAcknowledged.value) return
  recoveryCodesVisible.value = false
}
</script>

<template>
  <PageHeader :title="t('identity.security.title')" :subtitle="t('identity.security.subtitle')" />

  <div class="max-w-3xl space-y-6">
    <Alert
      v-if="recoveryCodesVisible && new_recovery_codes?.length"
      :title="t('identity.security.recoveryCodesOneTimeTitle')"
    >
      <div class="space-y-4">
        <p>{{ t('identity.security.recoveryCodesOneTimeHint') }}</p>
        <ol
          class="grid grid-cols-2 gap-x-6 gap-y-2 rounded-lg border bg-muted/40 p-4 font-mono text-sm sm:grid-cols-3"
          :aria-label="t('identity.security.recoveryCodesOneTimeTitle')"
        >
          <li v-for="code in new_recovery_codes" :key="code">{{ code }}</li>
        </ol>
        <p v-if="recoveryCodesFeedback" role="status" class="text-sm font-medium">
          {{ recoveryCodesFeedback }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button type="button" variant="outline" @click="copyRecoveryCodes">
            {{ t('identity.security.copyRecoveryCodes') }}
          </Button>
          <Button type="button" variant="outline" @click="downloadRecoveryCodes">
            {{ t('identity.security.downloadRecoveryCodes') }}
          </Button>
        </div>
        <label class="flex items-start gap-2 text-sm">
          <Checkbox v-model="recoveryCodesAcknowledged" class="mt-0.5" />
          <span>{{ t('identity.security.recoveryCodesAcknowledgement') }}</span>
        </label>
        <Button
          type="button"
          :disabled="!recoveryCodesAcknowledged"
          @click="dismissRecoveryCodes"
        >
          {{ t('identity.security.finishRecoveryCodes') }}
        </Button>
      </div>
    </Alert>

    <section class="space-y-4 rounded-xl border bg-card p-5 shadow-sm">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="font-semibold">{{ t('identity.security.emailTitle') }}</h2>
          <p class="mt-1 text-sm text-muted-foreground">{{ t('identity.security.emailHint') }}</p>
          <p class="mt-2 break-all text-sm font-medium">{{ email }}</p>
        </div>
        <Badge :variant="email_verified ? 'success' : 'secondary'">
          {{ email_verified ? t('identity.security.verified') : t('identity.security.unverified') }}
        </Badge>
      </div>

      <div v-if="!email_verified">
        <Button as-child variant="outline" size="sm">
          <Link :href="routes.resendVerification">{{ t('identity.resendVerification.submit') }}</Link>
        </Button>
      </div>

      <form class="grid gap-4 border-t pt-4 md:grid-cols-2" @submit.prevent="changeEmail">
        <div class="space-y-2 md:col-span-2">
          <h3 class="font-medium">{{ t('identity.security.changeEmailTitle') }}</h3>
          <p class="text-sm text-muted-foreground">{{ t('identity.security.changeEmailHint') }}</p>
        </div>
        <div class="space-y-2 md:col-span-2">
          <Label for="new_email">{{ t('identity.security.newEmail') }}</Label>
          <Input
            id="new_email"
            v-model="emailForm.email_change.email"
            type="email"
            autocomplete="email"
            required
          />
        </div>
        <div class="space-y-2">
          <Label for="email_password">{{ t('auth.signIn.password') }}</Label>
          <Input
            id="email_password"
            v-model="emailForm.email_change.password"
            type="password"
            autocomplete="current-password"
            required
          />
        </div>
        <div v-if="totp_enabled" class="space-y-2">
          <Label for="email_code">{{ t('auth.signIn.totp') }}</Label>
          <Input
            id="email_code"
            v-model="emailForm.email_change.code"
            autocomplete="one-time-code"
            required
          />
        </div>
        <div class="md:col-span-2">
          <Button type="submit" :disabled="emailForm.processing">
            {{ t('identity.security.changeEmail') }}
          </Button>
        </div>
      </form>
    </section>

    <section class="space-y-4 rounded-xl border bg-card p-5 shadow-sm">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="font-semibold">{{ t('identity.security.totpTitle') }}</h2>
          <p class="mt-1 text-sm text-muted-foreground">{{ t('identity.security.totpHint') }}</p>
        </div>
        <Badge :variant="totp_enabled ? 'success' : 'secondary'">
          {{ totp_enabled ? t('identity.security.enabled') : t('identity.security.disabled') }}
        </Badge>
      </div>

      <Alert v-if="require_totp && !totp_enabled" variant="destructive">
        {{ t('identity.security.requiredNotice') }}
      </Alert>

      <template v-if="pending_totp && !totp_enabled">
        <div class="grid gap-4 md:grid-cols-[auto,1fr]">
          <div class="rounded-lg border bg-white p-3" v-html="pending_totp.qr_svg" />
          <div class="space-y-2 text-sm">
            <p>{{ t('identity.security.scanQr') }}</p>
            <p class="break-all font-mono text-xs text-muted-foreground">{{ pending_totp.secret }}</p>
          </div>
        </div>
        <form class="flex flex-wrap items-end gap-3" @submit.prevent="confirmTotp">
          <div class="space-y-2">
            <Label for="confirm_code">{{ t('auth.signIn.totp') }}</Label>
            <Input
              id="confirm_code"
              v-model="confirmForm.totp.code"
              autocomplete="one-time-code"
              required
            />
          </div>
          <Button type="submit" :disabled="confirmForm.processing">
            {{ t('identity.security.confirmTotp') }}
          </Button>
        </form>
      </template>

      <div v-else-if="!totp_enabled">
        <Button type="button" @click="startSetup">{{ t('identity.security.startTotp') }}</Button>
      </div>

      <template v-else>
        <Alert :title="t('identity.security.recoveryCodesTitle')">
          {{ t('identity.security.recoveryCodesRemaining', { count: recovery_codes_remaining }) }}
        </Alert>

        <form class="grid gap-4 rounded-lg bg-muted/35 p-4 md:grid-cols-2" @submit.prevent="regenerateRecoveryCodes">
          <div class="space-y-1 md:col-span-2">
            <h3 class="font-medium">{{ t('identity.security.regenerateRecoveryCodes') }}</h3>
            <p class="text-sm text-muted-foreground">
              {{ t('identity.security.regenerateRecoveryCodesHint') }}
            </p>
          </div>
          <div class="space-y-2">
            <Label for="recovery_password">{{ t('auth.signIn.password') }}</Label>
            <Input
              id="recovery_password"
              v-model="recoveryCodesForm.recovery_codes.password"
              type="password"
              autocomplete="current-password"
              required
            />
          </div>
          <div class="space-y-2">
            <Label for="recovery_code">{{ t('auth.signIn.totp') }}</Label>
            <Input
              id="recovery_code"
              v-model="recoveryCodesForm.recovery_codes.code"
              autocomplete="one-time-code"
              required
            />
          </div>
          <div class="md:col-span-2">
            <Button type="submit" variant="outline" :disabled="recoveryCodesForm.processing">
              {{ t('identity.security.regenerateRecoveryCodes') }}
            </Button>
          </div>
        </form>

        <form class="grid gap-4 border-t pt-4 md:grid-cols-2" @submit.prevent="disableTotp">
          <div class="space-y-1 md:col-span-2">
            <h3 class="font-medium">{{ t('identity.security.disableTotp') }}</h3>
            <p class="text-sm text-muted-foreground">{{ t('identity.security.disableTotpHint') }}</p>
          </div>
          <div class="space-y-2">
            <Label for="disable_password">{{ t('auth.signIn.password') }}</Label>
            <Input
              id="disable_password"
              v-model="disableForm.totp.password"
              type="password"
              autocomplete="current-password"
              required
            />
          </div>
          <div class="space-y-2">
            <Label for="disable_code">{{ t('auth.signIn.totp') }}</Label>
            <Input
              id="disable_code"
              v-model="disableForm.totp.code"
              autocomplete="one-time-code"
              required
            />
          </div>
          <div class="md:col-span-2">
            <Button type="submit" variant="destructive" :disabled="disableForm.processing">
              {{ t('identity.security.disableTotp') }}
            </Button>
          </div>
        </form>
      </template>
    </section>

    <section class="space-y-4 rounded-xl border border-destructive/40 bg-card p-5 shadow-sm">
      <div>
        <h2 class="font-semibold text-destructive">{{ t('identity.security.closeAccountTitle') }}</h2>
        <p class="mt-1 text-sm text-muted-foreground">{{ t('identity.security.closeAccountHint') }}</p>
      </div>

      <ul class="list-disc space-y-1 pl-5 text-sm text-muted-foreground">
        <li>{{ t('identity.security.closeAccountProfile') }}</li>
        <li>{{ t('identity.security.closeAccountContent') }}</li>
        <li>{{ t('identity.security.closeAccountRecords') }}</li>
        <li>{{ t('identity.security.closeAccountSessions') }}</li>
      </ul>

      <form class="grid gap-4 border-t pt-4 md:grid-cols-2" @submit.prevent="closeAccount">
        <fieldset class="space-y-3 md:col-span-2">
          <legend class="text-sm font-medium">{{ t('identity.security.closeAccountContentChoice') }}</legend>
          <label class="flex cursor-pointer items-start gap-3 rounded-xl border p-4">
            <input
              v-model="accountCloseForm.account_close.closure_mode"
              type="radio"
              value="anonymize"
              class="mt-1"
            />
            <span>
              <span class="block text-sm font-medium">{{ t('identity.security.closeAccountAnonymize') }}</span>
              <span class="mt-1 block text-sm text-muted-foreground">
                {{ t('identity.security.closeAccountAnonymizeHint') }}
              </span>
            </span>
          </label>
          <label class="flex cursor-pointer items-start gap-3 rounded-xl border p-4">
            <input
              v-model="accountCloseForm.account_close.closure_mode"
              type="radio"
              value="delete_content"
              class="mt-1"
            />
            <span>
              <span class="block text-sm font-medium">{{ t('identity.security.closeAccountDeleteContent') }}</span>
              <span class="mt-1 block text-sm text-muted-foreground">
                {{ t('identity.security.closeAccountDeleteContentHint') }}
              </span>
            </span>
          </label>
          <p class="text-sm text-muted-foreground">
            {{ t('identity.security.closeAccountLegalHoldHint') }}
          </p>
        </fieldset>
        <div class="space-y-2">
          <Label for="close_password">{{ t('auth.signIn.password') }}</Label>
          <Input
            id="close_password"
            v-model="accountCloseForm.account_close.password"
            type="password"
            autocomplete="current-password"
            required
          />
        </div>
        <div v-if="totp_enabled" class="space-y-2">
          <Label for="close_code">{{ t('auth.signIn.totp') }}</Label>
          <Input
            id="close_code"
            v-model="accountCloseForm.account_close.code"
            autocomplete="one-time-code"
            required
          />
        </div>
        <div class="space-y-2 md:col-span-2">
          <Label for="close_confirmation">{{ t('identity.security.closeAccountConfirmation') }}</Label>
          <Input
            id="close_confirmation"
            v-model="accountCloseForm.account_close.confirmation"
            autocomplete="off"
            :placeholder="t('identity.security.closeAccountConfirmationPlaceholder')"
            required
          />
        </div>
        <div class="space-y-2 md:col-span-2">
          <Label for="close_reason">{{ t('identity.security.closeAccountReason') }}</Label>
          <Textarea
            id="close_reason"
            v-model="accountCloseForm.account_close.reason"
            :placeholder="t('identity.security.closeAccountReasonPlaceholder')"
          />
        </div>
        <div class="md:col-span-2">
          <Button type="submit" variant="destructive" :disabled="accountCloseForm.processing">
            {{ t('identity.security.closeAccount') }}
          </Button>
        </div>
      </form>
    </section>

    <div class="flex gap-3">
      <Button as-child variant="outline">
        <Link :href="routes.identityDataExports">{{ t('identity.dataExports.title') }}</Link>
      </Button>
      <Button as-child variant="outline">
        <Link :href="routes.sessionsManagement">{{ t('identity.sessions.title') }}</Link>
      </Button>
    </div>
  </div>
</template>
