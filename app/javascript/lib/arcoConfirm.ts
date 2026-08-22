import { Modal } from '@mcweb/ui'

export interface ConfirmOptions {
  title: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
  variant?: 'default' | 'destructive'
}

/**
 * Application confirmation facade backed by Arco Modal.
 *
 * It intentionally keeps the existing Promise<boolean> contract so admin
 * mutations can await a decision without falling back to a local dialog.
 */
export function confirm(options: ConfirmOptions): Promise<boolean> {
  return new Promise((resolve) => {
    let settled = false
    const finish = (value: boolean) => {
      if (settled) return
      settled = true
      resolve(value)
    }

    const config = {
      title: options.title,
      content: options.message,
      okText: options.confirmLabel,
      cancelText: options.cancelLabel,
      hideCancel: false,
      okButtonProps: options.variant === 'destructive' ? { status: 'danger' as const } : undefined,
      onOk: () => finish(true),
      onCancel: () => finish(false),
      onClose: () => finish(false),
    }

    if (options.variant === 'destructive') {
      Modal.warning(config)
    } else {
      Modal.confirm(config)
    }
  })
}
