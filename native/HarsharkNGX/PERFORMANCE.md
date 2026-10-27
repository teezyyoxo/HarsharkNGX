# Native performance measurements

Measured 2026-10-26 on macOS-26.7-arm64-arm-64bit-Mach-O. Release Swift package, three fresh processes per synthetic workload; medians below. Import includes HARRow creation. RSS values use Mach task info and getrusage (bytes on macOS).

| Workload | File MiB | Requests | Import ms | Filter ms | Sort ms | Preview ms | Peak RSS MiB | RSS after release MiB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| small | 1.18 | 1000 | 14.93 | 7.72 | 0.11 | 0.04 | 11.91 | 10.72 |
| medium | 41.08 | 10000 | 190.65 | 52.61 | 3.87 | 0.09 | 70.53 | 29.44 |
| many_entries | 58.97 | 50000 | 561.76 | 246.24 | 33.36 | 0.10 | 172.16 | 90.45 |
| large_preview | 4.00 | 1 | 8.50 | 2.51 | 0.00 | 5.84 | 20.47 | 16.45 |
| large_body | 33.00 | 1 | 42.15 | 2.57 | 0.00 | 0.00 | 41.36 | 8.34 |

The 33 MiB body is deliberately refused by the 8 MiB preview budget; its preview time measures that check, not decoding. The 4 MiB large_preview workload measures actual decoding. Baseline RSS is approximately 5.6 MiB. Metadata grows with entry count. RSS remaining after scope exit includes allocator/runtime retention; it is not proof that captures are still referenced. A separate weak-reference regression verifies release of mapped backing storage after the last body reference is dropped.

These are core-process measurements, not Instruments traces or full GUI memory measurements. Filtering is metadata-only; sorting uses duration. They do not include SwiftUI/AppKit, debounce latency, rendering, body searches, disk cold-cache conditions, or a Python comparison. No cross-implementation improvement is claimed.

Reproduce from the native directory:

```sh
swift build -c release --product harshark-benchmark
python3 scripts/benchmark.py .build/release/harshark-benchmark
```

Fixtures are generated in a temporary directory and removed automatically. Raw measurements are in PERFORMANCE.json.
