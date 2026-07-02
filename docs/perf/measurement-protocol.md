# Out-of-band 3G measurement protocol (issue #27, G5)

**Manual / periodic — NOT run in CI.** Hosted runners cannot emulate a cellular
radio deterministically, so the physical-link wall-clock of the scan → display
NFR (PRD §5) is measured out-of-band and recorded as evidence in
[`decryption-budget.md`](./decryption-budget.md) (§ Field measurements). This
validates the analytical network model against reality and feeds the pilot (#31)
and the ARTCI homologation dossier (#30).

Run it before the pilot, and again whenever the reference `3G-STABLE` profile,
the record schema (#15), or the compression path (#24) changes materially.

## Reference profile to reproduce

```
3G-STABLE = { goodput = 750 kbit/s (application-layer), rtt = 150 ms }
```

For a symmetric emulation, throttle **both** directions and add the RTT as
one-way delay ≈ RTT/2 on each side (≈ 75 ms each). Confirm the effective
throughput with a control transfer before timing the flow.

## A — Android emulator / device (`app-patient`, Flutter) — available now

1. **Shape the link.** On a Linux host, apply `tc` + `netem` to the emulator's
   egress/ingress interface:

   ```bash
   # Downlink 750 kbit/s, ~75 ms one-way delay. Adjust IFACE to the emulator NIC.
   sudo tc qdisc add dev "$IFACE" root handle 1: tbf rate 750kbit burst 32kbit latency 400ms
   sudo tc qdisc add dev "$IFACE" parent 1:1 handle 10: netem delay 75ms
   # ... mirror on the ingress path (ifb) for the uplink.
   ```

   Or use Android Emulator network throttling (`Extended controls → Cellular →
   Network type: UMTS`, or `telnet localhost 5554` → `network speed umts` /
   `network delay umts`) as a coarser alternative. Record which tool + exact
   settings were used.

2. **Prepare data.** Seed a worst-case ~500 Kio patient record (the fixture
   shape used by `app-patient/test/record/blob_size_budget_test.dart`). Use only
   **synthetic, non-nominative** data — never a real patient record.

3. **Measure `scan → displayed`.** Script the doctor flow (scan the QR →
   `ScanService` fetch+decrypt → record rendered) and stamp start at scan and end
   at first fully-rendered frame. Repeat ≥ 20× on a warm app; discard the first 3.

4. **Record** p50 and p95 in `decryption-budget.md` with date, device/emulator
   model, and the exact link settings. Note whether the target ≤ 3 s is met and
   the delta vs the modelled `T_total`.

> ⚠️ The QR **session** blob is uncompressed today (see the budget doc's Scope
> note). Until that follow-up lands, the doctor download reflects the *plaintext*
> size, not `MAX_BLOB_BYTES`; call this out explicitly in the recorded numbers so
> the model-vs-reality delta is not misread.

## B — Doctor PWA (`app-medecin`) — BLOCKED on #17

The PWA WASM decrypt path does not exist yet (`app-medecin/src/session.ts`,
`TODO(#17)`). When it lands:

1. Chrome DevTools → Network → throttling profile matching `3G-STABLE`
   (custom: 750 kbit/s down/up, 150 ms latency).
2. Use the Performance panel / `performance.now()` marks around scan → rendered.
3. Record p50/p95 in `decryption-budget.md` (PWA row) with the same rigour.

## Guardrails

- Synthetic data only; no real PII, keys, or nonces in fixtures, logs, or the
  recorded numbers — timings and sizes only.
- Nothing decrypted is written to disk; the record stays in RAM and the session
  is wiped at the end (consistent with #19).
- These measurements are **evidence**, not a gate — they never block CI.
