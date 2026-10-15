# Verification record

Date: 2026-10-16. Compiler: Solidity 0.8.26. Foundry: 1.8.3 (`cae51ad458f6abb64852b7709eb784352429825d`). The configured fuzz seed is `0x70400acffe2a4602ecfd12d07e8d6076229abeecfafc6e78631ab193db2b3f92`, with 256 cases per fuzz test. Real constructor execution is enabled by disabling dynamic test linking.

## Final results

| Check | Result |
| --- | --- |
| `forge build` | Pass |
| `forge build --offline --sizes` | Pass; no dependency download |
| Default Foundry tests | **46 passed, 0 failed, 0 skipped** |
| Actual mainnet-fork tests | **11 passed, 0 failed, 0 skipped** |
| `forge fmt --check` | Pass |
| Independent adversarial tests | 7 passed, including 256 fuzz cases; included in the default total |
| Runtime size | 1,384 bytes |
| External library links | None |
| Forbidden runtime instructions | No DELEGATECALL, CALLCODE, or SELFDESTRUCT in instruction-aware review |

Five fuzz tests provide 1,280 cases per full default run: full-width supply clamping, bounded supply/pixel comparisons, unsupported Craft IDs, unauthorized callers, and independent raw ABI/padding validation. Explicit tests also exercise all seven requested milestones and byte/word boundaries.

The review and check output here are builder evidence. IMD's independent verifier and deployment-stage checks retain their separate authority. The supplied protected floor requires deployment-manifest inputs that are produced later; this assignment's factory tests rehearse the application constructor and authority without claiming to be that attestation.

## Reproduction

Default suite, runnable with no network and no test environment configuration:

```sh
forge build
forge build --offline --sizes
FOUNDRY_FUZZ_SEED=0x70400acffe2a4602ecfd12d07e8d6076229abeecfafc6e78631ab193db2b3f92 \
  forge test -vv --gas-report
forge fmt --check
```

The seed is also pinned in `foundry.toml`, so plain `forge test` uses the same seed. Tests do not call environment or filesystem cheatcodes and do not require anything from `test/scratch/`.

Actual-mainnet integration, with an archive-capable RPC available:

```sh
FOUNDRY_PROFILE=mainnet \
FOUNDRY_FUZZ_SEED=0x70400acffe2a4602ecfd12d07e8d6076229abeecfafc6e78631ab193db2b3f92 \
  forge test --fork-url https://ethereum-rpc.publicnode.com \
  --fork-block-number 26200148 -vv
```

The profile changes only the test directory to `integration/`. It inherits the compiler and optimizer settings. Tests assert chain ID, pinned block, deployed code hashes and Craft state. They fail if run without the required fork; they never silently skip or substitute a mock Vessel. The offline default suite is deliberately separate.

## Mainnet evidence

- Block: **26,200,148**.
- Block hash: `0x6d19fe219bbccd71f6a6f8388b9611957c3a50d86a0da05e116278963d8e41ac`.
- Vessel: `0xECb92Cc7112b80A2234936315BbB493fb48d1463`.
- Vessel runtime hash: `0x991e261d56406937caf1763b003b962cbd11bab4e2dfd273926d91a11447f659`.
- Active renderer: `0x85c7D2933f178A02Ee9AAC0E654094EaDAca48a2`.
- Renderer runtime hash: `0xeb3af5bd334b536c7aed1633c42371e4acce9a105ae07f23c7178e7c7d68bbae`.
- Craft #10000 holder: `0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a`.
- Craft state: Machine type, grayscale mode 0, unlocked, no Relic override.

The ABI and verified source were retrieved from Blockscout for the exact deployed addresses. Each verified runtime was compared byte-for-byte with `eth_getCode` at the pinned mainnet block. Both verified Solidity sources match the public upstream commit after trimming trailing whitespace. Their verified compiler is 0.8.31; the existing deployed bytecode is used directly on the fork, so it is not recompiled with this project's 0.8.26 compiler.

The Machine interface is the two-method ABI in Vessel's source and the [official Machine template](https://www.thevessel.fun/docs/machines): `name()` and `craftToPayload(uint256)`. The renderer interprets byte value `v` as `rgb(v,v,v)` in grayscale mode, and its grid formula yields 100×100 for capacity 10,000. The payload's row-major interpretation was then verified through complete live-renderer output, not just assumed from documentation.

See [reference/provenance.json](reference/provenance.json), the adjacent full ABI/source snapshots, and [the pinned upstream source](https://github.com/producedbydav/The-Vessel/tree/b0cbb6c89f8c051648bdc2cd3df9ed05b5295e32). `sourceSHA256` hashes the saved source file; `verifiedSourceSHA256` hashes the original API source string before the saved trailing newline.

## Fork test coverage

The suite deploys the actual SelloutMachine bytecode locally, impersonates the real holder for `setMachineHolder(10000, machineAddress)`, and uses Vessel's real routing and renderer. Unauthorized attachment reverts. No `vm.etch`, `vm.store`, mock routing, lock bypass, renderer replacement, or mainnet broadcast is used.

After attachment it checks exact payload length and every byte at counts 0, 1, 100, 101, 5,000, 9,999, 10,000, and `uint256.max`. It also checks live supply changes, decreases, read failure fallback, and replacement collections without reattachment.

Seven SVG tests hash the complete output against an independent standard-library Python implementation, [tools/svg_vectors.py](../tools/svg_vectors.py). This validates every rectangle's coordinate and color as well as total output length. The tracked supply is a purpose-built mock, so the test does not attest the compatibility or truthfulness of a future collection selected by the owner.

## Evidence files and limits

- [unit-tests.txt](results/unit-tests.txt): complete final default-suite and gas-report output.
- [mainnet-fork.txt](results/mainnet-fork.txt): complete final fork-suite output.
- [build.txt](results/build.txt): final build and offline size check.
- [source-hashes.json](results/source-hashes.json): SHA-256 fingerprints of the application sources and Foundry configuration.
- [gas.md](gas.md): measurement scopes and the existing renderer's 422–471 million gas limitation.
- [security-review.md](security-review.md): independent reviewer findings and explicitly unperformed analysis.

There are no unresolved failed or blocked application/fork tests in the final runs. Forge's `reentrancy-events` lint warning was reviewed: every collection interaction is a bounded STATICCALL, which cannot change state or emit logs, and the event follows the successful state update. The independent owner-contract callback test confirms the relevant restriction. The pinned test library's `lastCallGas()` helper is supported but marked deprecated by Foundry 1.8.3; this affects test instrumentation only.

No mainnet deployment, source-verification transaction, GitHub publication, or Craft attachment was performed by this worker. These are not implied by a successful test run. Receipt items and responsibilities are recorded in [deployment.md](deployment.md).
