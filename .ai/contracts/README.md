# Frozen contracts

Governing freezes for **landed** work. Read these for what must stay true —
not how the series was implemented.

Queued work keeps its full spec under [../TODO/](../TODO/) until it lands.
Athena optics stays there: [../TODO/athena-optics-contract.md](../TODO/athena-optics-contract.md).

| File | Status | Owns |
|------|--------|------|
| [pipeline-contract.md](pipeline-contract.md) | **Implemented** | Feedback pipeline: features, protocols, lanes, Crown Start refused |
| [data-plane-contract.md](data-plane-contract.md) | **Implemented** | Capture fork, inner zstd, assemble, soak, Android FGS |
| [session-format-contract.md](session-format-contract.md) | **Implemented** | `.neurofeed` v5 bytes. Human spec: [../../README_feedback_format.md](../../README_feedback_format.md) |
| [fileformat_v6.md](fileformat_v6.md) | **Draft** (annotations + base vocabulary **LOCKED**) | Unified recording+feedback metadata; v6 clean cut (not implemented) |

Do not reopen Key Decisions. Intentional deviations need a written why
before merge.

Other frozen specs that are not in this folder yet:
[../connect-simulator-ux.md](../connect-simulator-ux.md),
[../audio-engine.md](../audio-engine.md),
[../monitor.md](../monitor.md),
[../trust-graphs.md](../trust-graphs.md).

How the code is laid out today: [../architecture.md](../architecture.md),
[../feedback/architecture.md](../feedback/architecture.md).
Historical PR order: [../archive/](../archive/).
