# Sellout Machine test contribution

This contribution tests the accepted implementation without changing application source,
configuration, dependencies, or the existing tests. All delivered changes are under `test/`.
The test contributor reviewed `src/SelloutMachine.sol` and `src/interfaces/IMachine.sol`
independently of their author, using the supplied property-testing references and protected
checks as review inputs.

## Results

Foundry 1.8.3, Solidity 0.8.26, existing Cancun/optimizer settings, seed
`0x70400acffe2a4602ecfd12d07e8d6076229abeecfafc6e78631ab193db2b3f92`:

| Check | Result |
| --- | --- |
| `forge build --offline` | Pass |
| Full default suite, including gas report | 65 passed, 0 failed, 0 skipped |
| New tests within that total | 19 passed |
| Stateless fuzz cases | 3,280: five existing tests at 256 and two new tests at 1,000 |
| Stateful invariant | 256 sequences, depth 64, 16,384 actions, zero unexpected reverts |
| Existing actual-mainnet integration suite | 11 passed, 0 failed, 0 skipped |
| Independent Python SVG vectors | All seven lengths and SHA-256 values match the fork fixtures |

Raw output: [build](results/build.txt), [offline tests and gas report](results/offline-tests.txt),
and [mainnet fork](results/mainnet-fork.txt). These are local reproduction records, not deployment
attestations. No mainnet transaction, attachment, deployment, or GitHub publication was performed
by this bounded tests assignment.

## Added coverage

- `ResponseValidation.t.sol` varies each ERC-165 stage independently, including the invalid
  interface ID check. It covers canonical/wrong/non-boolean words; lengths 0, 1, 31, 32, 33, 64,
  and 65,536; and independent revert, gas exhaustion, SSTORE, LOG, and TSTORE attempts.
  Two 1,000-run fuzz properties vary interface responses and totalSupply return length/value.
  Exact 32-byte *revert* data cannot masquerade as a successful supply read.
- Failed configuration must preserve the prior selection and emit no event. Re-selecting the
  current collection must emit accurate previous/new addresses and revalidate the collection.
  A forwarder called with the owner's `tx.origin` remains unauthorized. Unsupported Craft IDs
  must fail before reading a hostile supply. Payload generation must read supply exactly once
  and write no Machine or collection storage.
- `SelloutMachineInvariant.t.sol` drives three collections and three unauthorized actors through
  supply changes, burns, replacement, invalid selection, and malicious behavior/recovery in
  random order. Ghost selection, raw supplies, and read health come from handler actions rather
  than Machine getters. After every action, the owner, selected collection, bounded count,
  basis points, complete pixel image, and absence of collection storage writes must agree with
  that model. Expected errors are decoded explicitly; unexpected handler reverts fail the test.
  A deterministic lifecycle also proves the handler exercises successful and failed transitions.
- `OfflineVesselCompatibility.t.sol` adds a clearly labeled local adapter for holder attachment,
  IMachine ABI dispatch, and 100x100 grayscale SVG rendering. It checks collection replacement,
  burns, read failure/recovery, unsupported Craft errors, and complete independent SVG hashes
  at counts 101 and 9,999. This limited model omits delegates, locking, Relics, other Craft types,
  and metadata. Its gas usage is not a benchmark of the deployed Vessel.

Existing tests continue to cover all seven requested milestones, every assembly alignment,
raw ABI length/padding, maximum uint256 clamping, factory ownership, return/revert bombs,
recursive reads, owner-contract callbacks, and direct gas ceilings.

## Actual-mainnet integration

The existing `integration/VesselMainnet.t.sol` was executed against Ethereum mainnet block
**26,200,148**, hash
`0x6d19fe219bbccd71f6a6f8388b9611957c3a50d86a0da05e116278963d8e41ac`.
The suite checks chain ID, block number, Vessel/renderer runtime hashes, Craft ownership,
Machine type, grayscale mode, unlocked state, and absence of a Relic override before attaching.

It uses the actual Vessel at `0xECb92Cc7112b80A2234936315BbB493fb48d1463`, impersonates the
specified holder solely on the fork, and verifies authorization, live payload routing,
collection replacement without reattachment, burns, failed reads, and all seven full SVG hashes.
No deployed Vessel code or storage was overwritten, no renderer was substituted, and nothing
was broadcast. The supplied ABI/source snapshots were inspected to confirm Machine dispatch,
grayscale `rgb(v,v,v)` encoding, and row-major ordering.

The **first attempt failed in setup** through `https://ethereum-rpc.publicnode.com`:
the provider returned error `-32000`, historical state
`4cce88bc9a2495eebc16bb243a53f403fee6da3488f69ca9e367d9e55fc15c81` unavailable.
No application assertions ran in that attempt. A second run at the same block through
`https://rpc.flashbots.net` completed all **11 tests successfully**; its raw output is retained.

The default profile is entirely offline; the pre-existing `mainnet` profile selects `integration/`
and requires an explicitly supplied archival RPC. A plain offline `forge test` does not silently
claim fork coverage or need an RPC URL. Future archive-provider availability is not guaranteed.

## Adversarial review and limits

No reproducible application defect was found. This is a manual source review plus executable
adversarial tests, not a formal proof or a claim of exhaustive security coverage.

| Area | Review conclusion and evidence |
| --- | --- |
| Authority | Explicit nonzero constructor owner; immutable thereafter. Existing factory tests and the new owner-origin forwarder test exclude factory/msg.sender/tx.origin authority mistakes. Actual deployment arguments still need deployment-stage verification. |
| External calls | ERC-165 reads are capped at 30,000 gas each; supply reads at 100,000. STATICCALL prohibits nested state changes. Stage-specific tests cover persistent/transient writes and logs, in addition to the existing callbacks and gas bombs. |
| Return data | Copies only one word and requires exactly 32 returned bytes plus successful call status. New length/value fuzzing and one-word revert tests supplement existing large return/revert bombs. |
| Pixel memory | A zeroed black prefix plus white suffix is checked against independent per-byte oracles, including all tail alignments in existing tests. Exact ABI padding tests guard memory writes beyond the 10,000-byte payload. |
| State and custody | The Machine has no balances, shares, debts, token transfers, payable entry points, or custodial operations. Financial conservation invariants are inapplicable; the added invariant instead checks authority and image consistency over random transitions. |
| Static lint | Forge's event-after-external-call warning remains. The external interactions are bounded STATICCALLs; callback and log/write tests confirm they cannot reconfigure state or fabricate nested events. |

ERC-165 claims cannot prove that a collection is an honest ERC-721 or that its reported supply
is truthful. Future configured collections are not certified by these fixtures. Burns can reverse
progress. A failed, malformed, or over-budget supply read displays white, indistinguishable in
the image from a genuine zero supply, and recovers when the collection becomes readable again.
Immutable ownership deliberately has no recovery or transfer mechanism.

The protected floor files were read; their environment-driven deployment attestation was not
executed because this assignment supplies no deployment manifest inputs. Existing CREATE2
factory tests exercise the explicit-owner constructor independently of those launch-stage checks.

## Measured gas and external renderer constraint

The retained default-suite output reports these cold direct calls, including caller ABI decoding:

| Supply | Payload call gas |
| ---: | ---: |
| 0 | 45,553 |
| 1 | 45,493 |
| 100 | 45,106 |
| 101 | 45,046 |
| 5,000 | 34,309 |
| 9,999 | 23,125 |
| 10,000 | 23,065 |

Gas-exhausting supply fallback costs **140,599** gas, below the existing 160,000 ceiling.
First selection costs **56,739**, replacement **42,156**, and standalone CREATE **387,288** gas.
These measurements exclude transaction intrinsic gas and IMD factory overhead. The normal
supply fixture and malicious fixtures have different read costs; these are not universal bounds
for arbitrarily underfunded calls.

On the actual fork, full SVG calls cost **422,513,100–470,553,365 gas**, with
**598,122–658,122 bytes** of returned SVG. The pinned block's gas limit is **60,000,000**.
This is an existing external renderer limitation: full rendering exceeds that transaction gas
limit and may exceed a public RPC's eth_call cap. Foundry successfully evaluating it with a large
allowance does not establish public-RPC or marketplace availability. The efficient Machine
payload and the expensive Vessel renderer are measured separately; no Machine test blesses
the renderer as inexpensive.

## Reproduction

No dependencies were added. The existing tracked forge-std files suffice with no network.
These artifact/cache overrides keep all generated files inside the disposable test directory:

```sh
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache forge build --offline
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache \
FOUNDRY_FUZZ_SEED=0x70400acffe2a4602ecfd12d07e8d6076229abeecfafc6e78631ab193db2b3f92 \
forge test --offline --gas-report

FOUNDRY_PROFILE=mainnet FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache \
FOUNDRY_FUZZ_SEED=0x70400acffe2a4602ecfd12d07e8d6076229abeecfafc6e78631ab193db2b3f92 \
forge test --fork-url https://rpc.flashbots.net --fork-block-number 26200148 --no-storage-caching -vv

python3 tools/svg_vectors.py
```

Fuzz/invariant run counts for the new tests are embedded as Foundry inline annotations.
No tests modify environment variables, use FFI, fetch dependencies, or depend on scratch files.
