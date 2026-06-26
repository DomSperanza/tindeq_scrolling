const LAST_DEVICE_KEY = 'tindeq-games-last-device-id';

export function getLastDeviceId(): string | null {
  try {
    return localStorage.getItem(LAST_DEVICE_KEY);
  } catch {
    return null;
  }
}

export function saveLastDeviceId(id: string): void {
  try {
    localStorage.setItem(LAST_DEVICE_KEY, id);
  } catch {
    // ignore storage errors
  }
}
