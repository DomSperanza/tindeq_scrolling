import type {
  ConnectionState,
  DeviceInfo,
  ForceSample,
  InputProvider,
} from '@tindeq-games/game-api';
import { CapacitorBleTransport } from './capacitor-ble';
import { describeBattery } from './battery';
import { TindeqClient } from './client';
import { MockTransport } from './mock-transport';
import {
  getBluetoothSupport,
  getDefaultProviderKind,
  isNativeApp,
  type ProviderKind,
} from './platform';
import type { ConnectOptions, TindeqTransport } from './transport';
import { isWebBluetoothAvailable, WebBluetoothTransport } from './web-bluetooth';

export type { ConnectOptions } from './transport';
export type { ProviderKind } from './platform';

export interface CreateInputProviderOptions {
  kind?: ProviderKind;
  transport?: TindeqTransport;
}

function createTransport(kind: ProviderKind): TindeqTransport {
  if (kind === 'mock') return new MockTransport();
  if (kind === 'native-ble') return new CapacitorBleTransport();
  return new WebBluetoothTransport();
}

export function createInputProvider(options: CreateInputProviderOptions = {}): InputProvider {
  const kind = options.kind ?? getDefaultProviderKind();
  const transport = options.transport ?? createTransport(kind);

  return new TindeqInputProvider(
    transport,
    kind,
    kind === 'mock' ? (transport as MockTransport) : null,
  );
}

/** Second Progressor for 2-player. Defaults to real BLE; pass useMock only to simulate P2. */
export function createSecondInputProvider(options: { useMock?: boolean } = {}): InputProvider {
  if (options.useMock) {
    return createInputProvider({
      kind: 'mock',
      transport: new MockTransport({ baselineKg: 16, amplitudeKg: 12, phaseOffset: Math.PI * 0.65 }),
    });
  }
  return createInputProvider();
}

const RECONNECT_DELAYS_MS = [400, 1200, 2500];

class TindeqInputProvider implements InputProvider {
  private state: ConnectionState = 'disconnected';
  private latest: ForceSample | null = null;
  private deviceInfo: DeviceInfo = {};
  private sampleListeners = new Set<(sample: ForceSample) => void>();
  private stateListeners = new Set<(state: ConnectionState) => void>();
  private deviceInfoListeners = new Set<(info: DeviceInfo) => void>();
  private client: TindeqClient;
  private disconnectUnsub: (() => void) | null = null;
  private sessionPersistent = false;
  private wantStreaming = false;
  private reconnectGeneration = 0;
  private deviceInfoLoadGeneration = 0;
  private connectChain: Promise<void> = Promise.resolve();

  constructor(
    private transport: TindeqTransport,
    private kind: ProviderKind,
    private mockTransport: MockTransport | null,
  ) {
    this.client = new TindeqClient(transport);
    this.client.setWeightHandler((forceKg, time) => {
      const sample = { forceKg, time };
      this.latest = sample;
      for (const listener of this.sampleListeners) {
        listener(sample);
      }
    });
    this.client.setBatteryHandler((batteryMv) => {
      this.deviceInfo = { ...this.deviceInfo, batteryMv, batteryLow: false };
      this.notifyDeviceInfo();
    });
    this.client.setFirmwareHandler((firmware) => {
      this.deviceInfo = { ...this.deviceInfo, firmware };
      this.notifyDeviceInfo();
    });
    this.client.setLowPowerHandler(() => {
      this.deviceInfo = { ...this.deviceInfo, batteryLow: true };
      this.notifyDeviceInfo();
    });
  }

  getKind(): ProviderKind {
    return this.kind;
  }

  setSessionPersistence(enabled: boolean): void {
    this.sessionPersistent = enabled;
    if (!enabled) {
      this.reconnectGeneration += 1;
    }
  }

  async connect(options: ConnectOptions = {}): Promise<void> {
    this.reconnectGeneration += 1;

    let releaseConnect!: () => void;
    const turn = new Promise<void>((resolve) => {
      releaseConnect = resolve;
    });
    const previous = this.connectChain;
    this.connectChain = turn;
    await previous;

    try {
      await this.connectInternal(options);
    } finally {
      releaseConnect();
    }
  }

  private async connectInternal(options: ConnectOptions = {}): Promise<void> {
    const report = (message: string) => {
      console.info(`[Tindeq] ${message}`);
      options.onProgress?.(message);
    };

    this.setState('scanning');
    try {
      await this.client.connect({
        ...options,
        onProgress: (message) => {
          if (
            message.startsWith('Connecting') ||
            message.startsWith('Selected') ||
            message.startsWith('Reconnecting')
          ) {
            this.setState('connecting');
          }
          report(message);
        },
      });

      this.disconnectUnsub?.();
      this.disconnectUnsub = this.transport.onDisconnect?.(() => {
        this.handleUnexpectedDisconnect();
      }) ?? null;

      const deviceName = this.transport.getDeviceName?.() ?? undefined;
      this.deviceInfo = deviceName ? { deviceName } : {};

      this.setState('connected');
      this.notifyDeviceInfo();

      void this.loadDeviceInfoInBackground(report);
    } catch (error) {
      await this.client.disconnect({ sleep: false }).catch(() => {});
      this.deviceInfo = {};
      this.latest = null;
      this.setState('disconnected');
      this.notifyDeviceInfo();
      throw error;
    }
  }

  async disconnect(): Promise<void> {
    this.reconnectGeneration += 1;
    this.wantStreaming = false;
    this.sessionPersistent = false;
    this.disconnectUnsub?.();
    this.disconnectUnsub = null;
    await this.stopStreaming();
    await this.client.disconnect({ sleep: true });
    this.deviceInfo = {};
    this.latest = null;
    this.setState('disconnected');
    this.notifyDeviceInfo();
  }

  async tare(): Promise<void> {
    await this.client.tare();
  }

  async refreshDeviceInfo(): Promise<void> {
    if (this.state === 'disconnected') return;
    await this.client.send('GET_BATT_VLTG');
    await this.client.send('GET_APP_VERSION');
  }

  private async loadDeviceInfoInBackground(report: (message: string) => void): Promise<void> {
    const generation = ++this.deviceInfoLoadGeneration;
    try {
      report('Reading battery and firmware…');
      await this.client.send('GET_BATT_VLTG');
      if (generation !== this.deviceInfoLoadGeneration || this.state !== 'connected') return;
      await this.client.send('GET_APP_VERSION');
    } catch (error) {
      console.warn('[Tindeq] Could not read device info', error);
    }
  }

  async startStreaming(): Promise<void> {
    this.deviceInfoLoadGeneration += 1;
    await this.client.send('START_WEIGHT_MEAS', false);
    this.mockTransport?.startStream();
    this.wantStreaming = true;
    this.setState('streaming');
  }

  async stopStreaming(): Promise<void> {
    if (this.state !== 'streaming') return;
    this.wantStreaming = false;
    this.mockTransport?.stopStream();
    await this.client.send('STOP_WEIGHT_MEAS', false);
    this.setState('connected');
  }

  getState(): ConnectionState {
    return this.state;
  }

  getLatestSample(): ForceSample | null {
    return this.latest;
  }

  getDeviceInfo(): DeviceInfo {
    return this.deviceInfo;
  }

  onSample(callback: (sample: ForceSample) => void): () => void {
    this.sampleListeners.add(callback);
    return () => this.sampleListeners.delete(callback);
  }

  onStateChange(callback: (state: ConnectionState) => void): () => void {
    this.stateListeners.add(callback);
    return () => this.stateListeners.delete(callback);
  }

  onDeviceInfoChange(callback: (info: DeviceInfo) => void): () => void {
    this.deviceInfoListeners.add(callback);
    return () => this.deviceInfoListeners.delete(callback);
  }

  private notifyDeviceInfo(): void {
    const info = { ...this.deviceInfo };
    for (const listener of this.deviceInfoListeners) {
      listener(info);
    }
  }

  private handleUnexpectedDisconnect(): void {
    const resumeStreaming = this.wantStreaming;
    this.disconnectUnsub?.();
    this.disconnectUnsub = null;
    this.mockTransport?.stopStream();
    this.deviceInfo = {};
    this.latest = null;
    this.setState('disconnected');
    this.notifyDeviceInfo();

    if (this.sessionPersistent && this.kind !== 'mock') {
      void this.scheduleReconnect(resumeStreaming);
    }
  }

  private async scheduleReconnect(resumeStreaming: boolean): Promise<void> {
    const generation = ++this.reconnectGeneration;

    for (const delayMs of RECONNECT_DELAYS_MS) {
      if (generation !== this.reconnectGeneration || !this.sessionPersistent) return;
      await sleep(delayMs);
      if (generation !== this.reconnectGeneration || !this.sessionPersistent) return;
      if (this.state !== 'disconnected') return;

      try {
        console.info('[Tindeq] Reconnecting after unexpected disconnect…');
        await this.connectInternal();
        if (generation !== this.reconnectGeneration || !this.sessionPersistent) return;
        if (resumeStreaming) {
          await this.startStreaming();
        }
        return;
      } catch (error) {
        console.warn('[Tindeq] Reconnect attempt failed', error);
      }
    }
  }

  private setState(state: ConnectionState): void {
    this.state = state;
    for (const listener of this.stateListeners) {
      listener(state);
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export {
  TindeqClient,
  MockTransport,
  WebBluetoothTransport,
  CapacitorBleTransport,
  describeBattery,
  getBluetoothSupport,
  getDefaultProviderKind,
  isNativeApp,
  isWebBluetoothAvailable,
};
export type { BatteryLevel, BatteryStatus } from './battery';
