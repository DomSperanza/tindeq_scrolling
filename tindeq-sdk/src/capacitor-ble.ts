import type { ConnectOptions, TindeqTransport } from './transport';
import { NAME_PREFIXES, NOTIFY_UUID, SERVICE_UUID, WRITE_UUID } from './protocol';

function reportProgress(options: ConnectOptions | undefined, message: string): void {
  console.info(`[Tindeq BLE native] ${message}`);
  options?.onProgress?.(message);
}

function isProgressorName(name: string | undefined): boolean {
  if (!name) return false;
  return NAME_PREFIXES.some((prefix) => name.startsWith(prefix));
}

async function loadBleClient() {
  const { BleClient } = await import('@capacitor-community/bluetooth-le');
  return BleClient;
}

export class CapacitorBleTransport implements TindeqTransport {
  private deviceId: string | null = null;
  private deviceName: string | null = null;
  private listeners = new Set<(data: DataView) => void>();
  private disconnectListeners = new Set<() => void>();
  private disconnectHandler: ((deviceId: string) => void) | null = null;

  async connect(options: ConnectOptions = {}): Promise<void> {
    const BleClient = await loadBleClient();
    await this.disconnect().catch(() => {});

    reportProgress(options, 'Initializing Bluetooth…');
    await BleClient.initialize();

    reportProgress(options, 'Select your Progressor…');
    const device = await this.requestDevice(BleClient, options);

    if (!options.showAllDevices && !isProgressorName(device.name)) {
      throw new Error(`Expected a Progressor device, got "${device.name ?? 'unknown'}"`);
    }

    this.deviceId = device.deviceId;
    this.deviceName = device.name ?? null;

    reportProgress(options, `Selected ${device.name ?? 'Progressor'}. Connecting…`);
    this.disconnectHandler = (id) => {
      if (id !== this.deviceId) return;
      this.teardown();
      for (const listener of this.disconnectListeners) {
        listener();
      }
    };
    await BleClient.connect(device.deviceId, this.disconnectHandler);

    reportProgress(options, 'Discovering Progressor services…');
    reportProgress(options, 'Enabling force data notifications…');
    await BleClient.startNotifications(
      device.deviceId,
      SERVICE_UUID,
      NOTIFY_UUID,
      (value) => {
        for (const listener of this.listeners) {
          listener(value);
        }
      },
    );
  }

  async disconnect(): Promise<void> {
    if (!this.deviceId) {
      this.teardown();
      return;
    }

    const BleClient = await loadBleClient();
    const id = this.deviceId;
    try {
      await BleClient.stopNotifications(id, SERVICE_UUID, NOTIFY_UUID);
    } catch {
      // device may already be gone
    }
    try {
      await BleClient.disconnect(id);
    } catch {
      // already disconnected
    }
    this.teardown();
  }

  async write(data: Uint8Array): Promise<void> {
    if (!this.deviceId) {
      throw new Error('Progressor not connected');
    }
    const BleClient = await loadBleClient();
    await BleClient.write(
      this.deviceId,
      SERVICE_UUID,
      WRITE_UUID,
      new DataView(data.buffer, data.byteOffset, data.byteLength),
    );
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
    return this.deviceName;
  }

  private async requestDevice(
    BleClient: Awaited<ReturnType<typeof loadBleClient>>,
    options: ConnectOptions,
  ) {
    if (options.showAllDevices) {
      return BleClient.requestDevice({
        optionalServices: [SERVICE_UUID],
      });
    }

    for (const namePrefix of NAME_PREFIXES) {
      try {
        return await BleClient.requestDevice({
          namePrefix,
          optionalServices: [SERVICE_UUID],
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message.includes('cancel') || message.includes('Cancel')) {
          throw new Error('Device selection cancelled');
        }
      }
    }

    return BleClient.requestDevice({
      namePrefix: 'Progressor',
      optionalServices: [SERVICE_UUID],
    });
  }

  private teardown(): void {
    this.deviceId = null;
    this.deviceName = null;
    this.disconnectHandler = null;
    this.listeners.clear();
  }
}
