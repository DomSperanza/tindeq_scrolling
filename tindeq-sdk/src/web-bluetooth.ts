/// <reference types="web-bluetooth" />

import { getLastDeviceId, saveLastDeviceId } from './device-prefs';
import type { ConnectOptions, TindeqTransport } from './transport';
import { NAME_PREFIXES, NOTIFY_UUID, SERVICE_UUID, WRITE_UUID } from './protocol';

function navigatorBluetooth(): Bluetooth | undefined {
  return 'bluetooth' in navigator ? navigator.bluetooth : undefined;
}

export interface BluetoothSupport {
  available: boolean;
  reason?: string;
}

export type { ConnectOptions } from './transport';

export function getWebBluetoothSupport(): BluetoothSupport {
  if (typeof navigator === 'undefined') {
    return { available: false, reason: 'Not running in a browser' };
  }
  if (!window.isSecureContext) {
    return { available: false, reason: 'Web Bluetooth requires HTTPS or localhost' };
  }
  if (!navigatorBluetooth()) {
    return {
      available: false,
      reason: 'Web Bluetooth not supported — use Chrome or Edge on desktop/Android',
    };
  }
  return { available: true };
}

export function isWebBluetoothAvailable(): boolean {
  return getWebBluetoothSupport().available;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isProgressorName(name: string | undefined): boolean {
  if (!name) return false;
  return NAME_PREFIXES.some((prefix) => name.startsWith(prefix));
}

function wrapConnectError(error: unknown): Error {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes('GATT Server is disconnected') || message.includes('GATT operation')) {
    return new Error(
      'Could not connect to Progressor GATT. Wake the device (press button), then try Connect again.',
    );
  }
  if (message.includes('User cancelled')) {
    return new Error('Device selection cancelled');
  }
  return error instanceof Error ? error : new Error(message);
}

function reportProgress(options: ConnectOptions | undefined, message: string): void {
  console.info(`[Tindeq BLE] ${message}`);
  options?.onProgress?.(message);
}

async function connectGattWithRetry(
  gatt: BluetoothRemoteGATTServer,
  options: ConnectOptions | undefined,
  attempts = 3,
): Promise<BluetoothRemoteGATTServer> {
  let lastError: unknown;

  for (let attempt = 0; attempt < attempts; attempt++) {
    const attemptLabel = attempt === 0 ? '' : ` (attempt ${attempt + 1}/${attempts})`;
    reportProgress(options, `Connecting to device${attemptLabel}…`);

    try {
      if (gatt.connected) {
        return gatt;
      }
      const server = await gatt.connect();
      await sleep(80);
      if (server.connected) {
        return server;
      }
    } catch (error) {
      lastError = error;
      if (attempt < attempts - 1) {
        const delayMs = 200 * (attempt + 1);
        reportProgress(options, `Connection failed, retrying in ${delayMs / 1000}s…`);
        await sleep(delayMs);
      }
    }
  }

  throw lastError ?? new Error('GATT connect failed after retries');
}

export class WebBluetoothTransport implements TindeqTransport {
  private device: BluetoothDevice | null = null;
  private server: BluetoothRemoteGATTServer | null = null;
  private writeChar: BluetoothRemoteGATTCharacteristic | null = null;
  private notifyChar: BluetoothRemoteGATTCharacteristic | null = null;
  private listeners = new Set<(data: DataView) => void>();
  private disconnectListeners = new Set<() => void>();
  private connecting = false;
  private onNotifyChanged = (event: Event) => {
    const target = event.target as unknown as BluetoothRemoteGATTCharacteristic;
    if (!target.value) return;
    for (const listener of this.listeners) {
      listener(target.value);
    }
  };
  private onGattDisconnected = () => {
    if (this.connecting) return;
    this.teardownGattRefs();
    for (const listener of this.disconnectListeners) {
      listener();
    }
  };

  async connect(options: ConnectOptions = {}): Promise<void> {
    const support = getWebBluetoothSupport();
    if (!support.available) {
      throw new Error(support.reason ?? 'Web Bluetooth unavailable');
    }

    this.connecting = true;
    try {
      await this.disconnect().catch(() => {});

      const fastConnected = await this.tryConnectKnownDevice(options);
      if (!fastConnected) {
        this.device = await this.pickDeviceFromPicker(options);
        await this.establishConnection(options);
      }

      if (this.device?.id) {
        saveLastDeviceId(this.device.id);
      }
    } catch (error) {
      await this.disconnect().catch(() => {});
      throw wrapConnectError(error);
    } finally {
      this.connecting = false;
    }
  }

  async disconnect(): Promise<void> {
    if (this.device) {
      this.device.removeEventListener('gattserverdisconnected', this.onGattDisconnected);
    }
    if (this.notifyChar) {
      this.notifyChar.removeEventListener('characteristicvaluechanged', this.onNotifyChanged);
    }
    if (this.server?.connected) {
      try {
        this.server.disconnect();
      } catch {
        // already disconnected
      }
    }
    this.listeners.clear();
    this.teardownGattRefs();
    this.device = null;
  }

  async write(data: Uint8Array): Promise<void> {
    if (!this.writeChar || !this.server?.connected) {
      throw new Error('Progressor not connected');
    }
    await this.writeChar.writeValue(new Uint8Array(data));
  }

  onNotify(callback: (data: DataView) => void): () => void {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  onDisconnect(callback: () => void): () => void {
    this.disconnectListeners.add(callback);
    return () => this.disconnectListeners.delete(callback);
  }

  getDeviceName(): string | null {
    return this.device?.name ?? null;
  }

  private async tryConnectKnownDevice(options: ConnectOptions): Promise<boolean> {
    if (options.showAllDevices) return false;

    const device = await this.findBestKnownProgressor();
    if (!device) return false;

    reportProgress(
      options,
      `Reconnecting to ${device.name ?? 'Progressor'} (skipping device picker)…`,
    );
    this.device = device;

    try {
      await this.establishConnection(options);
      return true;
    } catch (error) {
      console.warn('[Tindeq BLE] Fast reconnect failed, falling back to picker', error);
      this.teardownGattRefs();
      this.device = null;
      return false;
    }
  }

  private async establishConnection(options: ConnectOptions): Promise<void> {
    if (!this.device?.gatt) {
      throw new Error('Selected device does not support Bluetooth GATT');
    }

    if (!options.showAllDevices && !isProgressorName(this.device.name)) {
      throw new Error(`Expected a Progressor device, got "${this.device.name ?? 'unknown'}"`);
    }

    const name = this.device.name ?? 'Progressor';
    reportProgress(options, `Selected ${name}. Establishing Bluetooth link…`);
    this.server = await connectGattWithRetry(this.device.gatt, options);
    reportProgress(options, 'Discovering Progressor services…');
    const service = await this.server.getPrimaryService(SERVICE_UUID);
    this.writeChar = await service.getCharacteristic(WRITE_UUID);
    this.notifyChar = await service.getCharacteristic(NOTIFY_UUID);

    reportProgress(options, 'Enabling force data notifications…');
    await this.notifyChar.startNotifications();
    this.notifyChar.addEventListener('characteristicvaluechanged', this.onNotifyChanged);
    this.device.addEventListener('gattserverdisconnected', this.onGattDisconnected);
  }

  private async pickDeviceFromPicker(options: ConnectOptions): Promise<BluetoothDevice> {
    reportProgress(
      options,
      'Wake the Progressor (press button), then pick it in the browser dialog…',
    );

    if (options.showAllDevices) {
      return navigatorBluetooth()!.requestDevice({
        acceptAllDevices: true,
        optionalServices: [SERVICE_UUID],
      });
    }

    return navigatorBluetooth()!.requestDevice({
      filters: [{ namePrefix: 'Progressor' }],
      optionalServices: [SERVICE_UUID],
    });
  }

  private async findBestKnownProgressor(): Promise<BluetoothDevice | undefined> {
    const bluetooth = navigatorBluetooth();
    if (!bluetooth?.getDevices) {
      return undefined;
    }

    const devices = await bluetooth.getDevices();
    const progressors = devices.filter((device) => isProgressorName(device.name));
    if (progressors.length === 0) return undefined;

    const lastId = getLastDeviceId();
    if (lastId) {
      const preferred = progressors.find((device) => device.id === lastId);
      if (preferred) return preferred;
    }

    return progressors[0];
  }

  private teardownGattRefs(): void {
    this.writeChar = null;
    this.notifyChar = null;
    this.server = null;
  }
}
