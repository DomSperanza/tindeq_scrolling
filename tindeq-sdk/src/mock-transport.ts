import type { TindeqTransport } from './transport';
import { Cmd } from './protocol';

export interface MockTransportOptions {
  baselineKg?: number;
  amplitudeKg?: number;
  intervalMs?: number;
  phaseOffset?: number;
}

export class MockTransport implements TindeqTransport {
  private connected = false;
  private streaming = false;
  private timer: ReturnType<typeof setInterval> | null = null;
  private listeners = new Set<(data: DataView) => void>();

  private phase: number;

  constructor(private options: MockTransportOptions = {}) {
    this.phase = options.phaseOffset ?? 0;
  }

  async connect(_options?: { showAllDevices?: boolean }): Promise<void> {
    await sleep(400);
    this.connected = true;
  }

  async disconnect(): Promise<void> {
    this.stopTimer();
    this.streaming = false;
    this.connected = false;
  }

  async write(_data: Uint8Array): Promise<void> {
    if (!this.connected) {
      throw new Error('Mock device not connected');
    }

    const cmd = _data[0] | (_data[1] << 8);
    if (cmd === Cmd.START_WEIGHT_MEAS && !this.streaming) {
      this.startTimer();
    }
    if (cmd === Cmd.STOP_WEIGHT_MEAS && !this.streaming) {
      this.stopTimer();
    }
  }

  onNotify(callback: (data: DataView) => void): () => void {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  onDisconnect(): () => void {
    return () => {};
  }

  getDeviceName(): string {
    return 'Mock Progressor';
  }

  startStream(): void {
    if (this.streaming) return;
    this.streaming = true;
    this.startTimer();
  }

  stopStream(): void {
    if (!this.streaming) return;
    this.streaming = false;
    this.stopTimer();
  }

  private startTimer(): void {
    if (this.timer) return;
    const intervalMs = this.options.intervalMs ?? 33;
    const baseline = this.options.baselineKg ?? 12;
    const amplitude = this.options.amplitudeKg ?? 6;

    this.timer = setInterval(() => {
      this.phase += 0.08;
      const weight = baseline + Math.sin(this.phase) * amplitude;
      this.emitWeight(weight);
    }, intervalMs);
  }

  private stopTimer(): void {
    if (!this.timer) return;
    clearInterval(this.timer);
    this.timer = null;
  }

  private emitWeight(weight: number): void {
    const buffer = new ArrayBuffer(10);
    const view = new DataView(buffer);
    view.setInt8(0, 1);
    view.setInt8(1, 8);
    view.setFloat32(2, weight, true);
    view.setUint32(6, performance.now() * 1000, true);

    for (const listener of this.listeners) {
      listener(view);
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
