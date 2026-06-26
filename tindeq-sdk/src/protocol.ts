export const SERVICE_UUID = '7e4e1701-1ea6-40c9-9dcc-13d34ffead57';
export const WRITE_UUID = '7e4e1703-1ea6-40c9-9dcc-13d34ffead57';
export const NOTIFY_UUID = '7e4e1702-1ea6-40c9-9dcc-13d34ffead57';
export const TARGET_DEVICE_NAME = 'Progressor';
export const NAME_PREFIXES = ['Progressor', 'Tindeq', 'TINDEQ'] as const;

/** Response types on the data characteristic (TLV tag byte). */
export const ResponseCode = {
  CMD_RESP: 0,
  WEIGHT_MEASURE: 1,
  LOW_PWR: 4,
} as const;

/** Control-point opcodes per https://tindeq.com/progressor_api/ */
export const Cmd = {
  TARE_SCALE: 0x64,
  START_WEIGHT_MEAS: 0x65,
  STOP_WEIGHT_MEAS: 0x66,
  START_PEAK_RFD_MEAS: 0x67,
  START_PEAK_RFD_MEAS_SERIES: 0x68,
  ADD_CALIB_POINT: 0x69,
  SAVE_CALIB: 0x6a,
  GET_APP_VERSION: 0x6b,
  GET_ERR_INFO: 0x6c,
  CLR_ERR_INFO: 0x6d,
  SLEEP: 0x6e,
  GET_BATT_VLTG: 0x6f,
} as const;

export type CmdKey = keyof typeof Cmd;

/** TLV command: tag (opcode) + length 0 for commands without a value payload. */
export function packCmd(cmd: number): Uint8Array {
  return new Uint8Array([cmd & 0xff, 0]);
}

export interface ParsedWeightSample {
  weight: number;
  useconds: number;
}

/** Parse TLV payload from the data characteristic notification. */
export function parseNotifyPayload(data: DataView): { kind: number; samples: ParsedWeightSample[] } {
  const kind = data.getUint8(0);
  const payloadSize = data.getUint8(1);
  const samples: ParsedWeightSample[] = [];
  const end = Math.min(2 + payloadSize, data.byteLength);

  for (let offset = 2; offset + 8 <= end; offset += 8) {
    samples.push({
      weight: data.getFloat32(offset, true),
      useconds: data.getUint32(offset + 4, true),
    });
  }

  return { kind, samples };
}

export function parseBatteryMv(data: DataView): number | undefined {
  if (data.byteLength < 6 || data.getUint8(0) !== ResponseCode.CMD_RESP) {
    return undefined;
  }
  const payloadSize = data.getUint8(1);
  if (payloadSize < 4) return undefined;
  const mv = data.getUint32(2, true);
  if (mv < 2000 || mv > 5000) return undefined;
  return mv;
}

export function parseFirmware(data: DataView): string | undefined {
  if (data.byteLength <= 2 || data.getUint8(0) !== ResponseCode.CMD_RESP) {
    return undefined;
  }
  const payloadSize = data.getUint8(1);
  const end = Math.min(2 + payloadSize, data.byteLength);
  if (end <= 2) return undefined;
  const bytes = new Uint8Array(data.buffer, data.byteOffset + 2, end - 2);
  const text = new TextDecoder()
    .decode(bytes)
    .replace(/\0/g, '')
    .replace(/[^\x20-\x7E]/g, '')
    .trim();
  return text || undefined;
}
