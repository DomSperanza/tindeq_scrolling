import type { BluetoothSupport } from './web-bluetooth';
import { getWebBluetoothSupport, isWebBluetoothAvailable } from './web-bluetooth';

export type ProviderKind = 'mock' | 'web-bluetooth' | 'native-ble';

interface CapacitorGlobal {
  isNativePlatform?: () => boolean;
}

export function isNativeApp(): boolean {
  if (typeof window === 'undefined') return false;
  const cap = (window as unknown as { Capacitor?: CapacitorGlobal }).Capacitor;
  return cap?.isNativePlatform?.() ?? false;
}

export function getDefaultProviderKind(): ProviderKind {
  if (isNativeApp()) return 'native-ble';
  if (isWebBluetoothAvailable()) return 'web-bluetooth';
  return 'mock';
}

export function getBluetoothSupport(): BluetoothSupport {
  if (isNativeApp()) {
    return { available: true };
  }
  return getWebBluetoothSupport();
}
