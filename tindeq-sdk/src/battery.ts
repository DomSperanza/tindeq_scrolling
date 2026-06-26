export type BatteryLevel = 'good' | 'fair' | 'low' | 'critical';

export interface BatteryStatus {
  mv: number;
  percent: number;
  level: BatteryLevel;
  label: string;
}

/** Approximate LiPo mapping for USB-rechargeable Progressor (3200–4200 mV). */
const MIN_MV = 3200;
const MAX_MV = 4200;

export function describeBattery(mv: number): BatteryStatus {
  const percent = Math.round(
    Math.min(100, Math.max(0, ((mv - MIN_MV) / (MAX_MV - MIN_MV)) * 100)),
  );

  if (mv < 3300) {
    return { mv, percent, level: 'critical', label: 'Charge now' };
  }
  if (mv < 3500) {
    return { mv, percent, level: 'low', label: 'Low' };
  }
  if (mv < 3800) {
    return { mv, percent, level: 'fair', label: 'Fair' };
  }
  return { mv, percent, level: 'good', label: 'Good' };
}
