/**
 * Referencyjny konektor TCP (klasa urzadzen sieciowych: ELM327 WiFi, ENET,
 * DoIP/13400, VAS6154-LAN, VXDIAG sieciowy). Przenosi sprawdzona logike z v1
 * (TCP_NODELAY, keep-alive) do kontraktu Connector.
 *
 * Docelowo odpowiednik w Go w apps/edge-agent; tu wersja TS jako referencja+test.
 */

import * as net from 'net';
import type { Connector, ConnectorEvents, DeviceConfig } from './connector';

interface TcpConfig extends DeviceConfig {
  host: string;
  port: number;
}

export class TcpConnector implements Connector {
  readonly kind = 'tcp' as const;
  private socket: net.Socket | null = null;
  private closed = false;

  open(config: DeviceConfig, events: ConnectorEvents): Promise<void> {
    const { host, port } = config as TcpConfig;
    return new Promise((resolve, reject) => {
      const sock = net.connect(port, host);
      this.socket = sock;
      sock.setNoDelay(true);           // male komendy diagnostyczne natychmiast
      sock.setKeepAlive(true, 15000);  // wykryj zerwany/wylaczony adapter
      sock.once('connect', () => resolve());
      sock.on('data', (chunk) => events.onData(chunk));
      sock.on('error', (err) => {
        if (!this.closed) { this.closed = true; events.onError(err); }
        reject(err);
      });
      sock.on('close', () => {
        if (!this.closed) { this.closed = true; events.onClose('urzadzenie rozlaczone'); }
      });
    });
  }

  write(chunk: Buffer): void {
    if (this.socket && !this.socket.destroyed) this.socket.write(chunk);
  }

  probe(config: DeviceConfig, timeoutMs = 1500): Promise<boolean> {
    const { host, port } = config as TcpConfig;
    return new Promise((resolve) => {
      const s = new net.Socket();
      let done = false;
      const finish = (ok: boolean) => { if (done) return; done = true; try { s.destroy(); } catch {} resolve(ok); };
      s.setTimeout(timeoutMs);
      s.once('connect', () => finish(true));
      s.once('timeout', () => finish(false));
      s.once('error', () => finish(false));
      try { s.connect(port, host); } catch { finish(false); }
    });
  }

  close(): void {
    this.closed = true;
    if (this.socket) { try { this.socket.destroy(); } catch {} this.socket = null; }
  }
}
