/**
 * WARSTWA KONEKTOROW — wspolny kontrakt transportu urzadzenia.
 * ----------------------------------------------------------------------------
 * Kazdy konektor opakowuje JEDEN sposob dostepu do urzadzenia diagnostycznego
 * (TCP, UDP, Serial/COM, USB-over-IP, J2534/PassThru, SocketCAN) w jednolity
 * dwukierunkowy strumien bajtow. Relay/Agent operuja wylacznie na tym
 * interfejsie i nie wiedza, jaki sprzet jest pod spodem.
 *
 * To jest KONTRAKT (TS). Implementacje produkcyjne: czesc w TS (ref/test),
 * docelowo w Go w apps/edge-agent. `tcp.ts` to referencyjna implementacja.
 */

export type ConnectorKind =
  | 'tcp' | 'udp' | 'serial' | 'usbip' | 'j2534' | 'socketcan';

export interface DeviceConfig {
  /** np. { host:'192.168.0.10', port:35000 } | { com:'COM3', baud:115200 } | { iface:'can0' } */
  [key: string]: unknown;
}

export interface ConnectorEvents {
  /** Bajty z urzadzenia -> do klienta. */
  onData: (chunk: Buffer) => void;
  /** Urzadzenie/transport zamkniete (z powodem). */
  onClose: (reason: string) => void;
  /** Blad transportu. */
  onError: (err: Error) => void;
}

/**
 * Pojedyncze, aktywne polaczenie do urzadzenia.
 * Cykl zycia: open() -> (write/onData)* -> close().
 */
export interface Connector {
  readonly kind: ConnectorKind;

  /** Nawiazuje polaczenie z urzadzeniem wg konfiguracji. Rzuca przy bledzie. */
  open(config: DeviceConfig, events: ConnectorEvents): Promise<void>;

  /** Klient -> urzadzenie. */
  write(chunk: Buffer): void;

  /** Sprawdza dostepnosc urzadzenia (np. testReachable dla TCP). */
  probe(config: DeviceConfig, timeoutMs?: number): Promise<boolean>;

  /** Zamyka polaczenie i zwalnia zasoby (zwalnia urzadzenie). */
  close(): void;
}

/** Rejestr konektorow — Agent wybiera implementacje po `kind`. */
export interface ConnectorRegistry {
  get(kind: ConnectorKind): Connector;
  register(kind: ConnectorKind, factory: () => Connector): void;
}

/**
 * Wymagania transportu wg klasy urzadzenia (patrz docs/ENTERPRISE-AUDIT.md §0):
 *  - tcp/udp        -> dziala wprost przez tunel,
 *  - serial/usbip/j2534/socketcan -> wymaga WIRTUALNEGO URZADZENIA po stronie
 *    klienta (COMx / shim DLL / vcan). Konektor po stronie HOSTA jest tylko
 *    polowa rozwiazania; druga polowa to client-agent.
 */
export const TRANSPORT_NEEDS_VIRTUAL_CLIENT: Record<ConnectorKind, boolean> = {
  tcp: false,
  udp: false,
  serial: true,
  usbip: true,
  j2534: true,
  socketcan: true,
};
