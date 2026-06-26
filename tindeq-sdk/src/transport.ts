export interface ConnectOptions {
  showAllDevices?: boolean;
  onProgress?: (message: string) => void;
}

export interface TindeqTransport {
  connect(options?: ConnectOptions): Promise<void>;
  disconnect(): Promise<void>;
  write(data: Uint8Array): Promise<void>;
  onNotify(callback: (data: DataView) => void): () => void;
  onDisconnect?(callback: () => void): () => void;
  getDeviceName?(): string | null;
}

export type TransportFactory = () => TindeqTransport;
