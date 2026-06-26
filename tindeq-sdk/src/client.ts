import type { ConnectOptions, TindeqTransport } from './transport';
import { Cmd, packCmd, parseBatteryMv, parseFirmware, parseNotifyPayload, ResponseCode } from './protocol';

type PendingCmd = 'GET_BATT_VLTG' | 'GET_APP_VERSION' | 'GET_ERR_INFO';
type QueueTask = () => Promise<void>;

const CMD_RESPONSE_TIMEOUT_MS = 5000;

export class TindeqClient {
  private tareValue = 0;
  private notifyUnsub: (() => void) | null = null;
  private onWeight: ((weight: number, time: number) => void) | null = null;
  private onBattery: ((mv: number) => void) | null = null;
  private onFirmware: ((version: string) => void) | null = null;
  private onLowPower: (() => void) | null = null;
  private pendingCmd: PendingCmd | null = null;
  private responseWaiters = new Map<PendingCmd, () => void>();
  private commandQueue: QueueTask[] = [];
  private drainingQueue = false;

  constructor(private transport: TindeqTransport) {}

  setWeightHandler(handler: (weight: number, time: number) => void): void {
    this.onWeight = handler;
  }

  setBatteryHandler(handler: (mv: number) => void): void {
    this.onBattery = handler;
  }

  setFirmwareHandler(handler: (version: string) => void): void {
    this.onFirmware = handler;
  }

  setLowPowerHandler(handler: () => void): void {
    this.onLowPower = handler;
  }

  async connect(options?: ConnectOptions): Promise<void> {
    this.notifyUnsub?.();
    this.notifyUnsub = null;
    await this.transport.connect(options);
    this.notifyUnsub = this.transport.onNotify((data) => this.handleNotify(data));
  }

  async disconnect(options: { sleep?: boolean } = {}): Promise<void> {
    this.commandQueue = [];
    this.drainingQueue = false;
    this.responseWaiters.clear();
    this.pendingCmd = null;
    if (options.sleep !== false) {
      try {
        await this.send('SLEEP', false);
      } catch {
        // device may already be gone
      }
    }
    this.notifyUnsub?.();
    this.notifyUnsub = null;
    await this.transport.disconnect();
  }

  async send(cmd: keyof typeof Cmd, trackResponse = cmd === 'GET_BATT_VLTG' || cmd === 'GET_APP_VERSION' || cmd === 'GET_ERR_INFO'): Promise<void> {
    await this.enqueue(async () => {
      const waitsForResponse =
        trackResponse &&
        (cmd === 'GET_BATT_VLTG' || cmd === 'GET_APP_VERSION' || cmd === 'GET_ERR_INFO');

      if (waitsForResponse) {
        this.pendingCmd = cmd;
        const responsePromise = this.waitForCmdResponse(cmd);
        await this.transport.write(packCmd(Cmd[cmd]));
        await responsePromise;
        this.pendingCmd = null;
        return;
      }

      this.pendingCmd = null;
      await this.transport.write(packCmd(Cmd[cmd]));
    });
  }

  /** Device-native tare (opcode 100 / TARE_SCALE). */
  async tare(): Promise<void> {
    await this.send('TARE_SCALE', false);
    this.tareValue = 0;
  }

  getTareValue(): number {
    return this.tareValue;
  }

  private waitForCmdResponse(cmd: PendingCmd): Promise<void> {
    return new Promise((resolve) => {
      const finish = () => {
        clearTimeout(timer);
        this.responseWaiters.delete(cmd);
        resolve();
      };

      const timer = setTimeout(() => {
        console.warn(`[Tindeq] Timed out waiting for ${cmd} response`);
        finish();
      }, CMD_RESPONSE_TIMEOUT_MS);

      this.responseWaiters.set(cmd, finish);
    });
  }

  private finishCmdResponse(cmd: PendingCmd | null): void {
    if (!cmd) return;
    const finish = this.responseWaiters.get(cmd);
    if (finish) {
      finish();
    }
  }

  private async enqueue(task: QueueTask): Promise<void> {
    return new Promise((resolve, reject) => {
      this.commandQueue.push(async () => {
        try {
          await task();
          resolve();
        } catch (error) {
          reject(error);
        }
      });
      void this.drainQueue();
    });
  }

  private async drainQueue(): Promise<void> {
    if (this.drainingQueue) return;
    this.drainingQueue = true;

    while (this.commandQueue.length > 0) {
      const task = this.commandQueue.shift();
      if (!task) break;
      await task();
      if (this.commandQueue.length > 0) {
        await sleep(100);
      }
    }

    this.drainingQueue = false;
  }

  private handleNotify(data: DataView): void {
    const kind = data.getUint8(0);

    if (kind === ResponseCode.WEIGHT_MEASURE) {
      const { samples } = parseNotifyPayload(data);
      for (const sample of samples) {
        const time = sample.useconds / 1_000_000;
        const weight = sample.weight - this.tareValue;
        this.onWeight?.(weight, time);
      }
      return;
    }

    if (kind === ResponseCode.CMD_RESP) {
      this.handleCmdResponse(data);
      return;
    }

    if (kind === ResponseCode.LOW_PWR) {
      this.onLowPower?.();
      return;
    }
  }

  private handleCmdResponse(data: DataView): void {
    const cmd = this.pendingCmd;

    if (cmd === 'GET_BATT_VLTG') {
      const mv = parseBatteryMv(data);
      if (mv !== undefined) this.onBattery?.(mv);
    } else if (cmd === 'GET_APP_VERSION') {
      const version = parseFirmware(data);
      if (version) this.onFirmware?.(version);
    } else if (!cmd) {
      // Late response after timeout — still try to apply useful data.
      const mv = parseBatteryMv(data);
      if (mv !== undefined) {
        this.onBattery?.(mv);
        return;
      }
      const version = parseFirmware(data);
      if (version) this.onFirmware?.(version);
      return;
    }

    this.finishCmdResponse(cmd);
    this.pendingCmd = null;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
