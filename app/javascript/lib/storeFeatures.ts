export type StoreFeatureId =
  | 'physical_products'
  | 'shipping'
  | 'gift_wrap'
  | 'order_shipping_management'

export type StoreFeaturesMap = Record<StoreFeatureId, boolean>

export const defaultStoreFeatures = (): StoreFeaturesMap => ({
  physical_products: false,
  shipping: false,
  gift_wrap: false,
  order_shipping_management: false,
})

export function resolveStoreFeatures(raw?: Partial<StoreFeaturesMap> | null): StoreFeaturesMap {
  const defaults = defaultStoreFeatures()
  if (!raw) return defaults

  return {
    physical_products: raw.physical_products === true,
    shipping: raw.shipping === true,
    gift_wrap: raw.gift_wrap === true,
    order_shipping_management: raw.order_shipping_management === true,
  }
}
