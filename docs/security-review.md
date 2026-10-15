# Independent adversarial review

Review date: 2026-10-16. A separate AI reviewer performed this review independently of the implementation work. This is a scoped code and test review, not a professional human audit or a guarantee of security.

## Scope and method

The review covered `src/SelloutMachine.sol`, `src/interfaces/IMachine.sol`, the Solidity 0.8.26 build configuration, the supplied deployment/ownership checks, the application unit tests, `integration/VesselMainnet.t.sol`, the saved Vessel/renderer verified source and ABI, and the requested deployment ownership model. The pinned `eth-security` material was considered as reference data. No production source was changed by the reviewer.

Manual analysis focused on the sole configuration entry point, immutable factory-independent ownership, external-call budgets, returndata handling, ERC-165 validation, callback behavior, supply clamping, byte ordering, payload allocation, and the absence of upgrade or asset-management authority. A separate scratch Foundry suite supplied adversarial contracts and checked raw ABI return data against a byte-by-byte reference.

## Findings

No exploitable defect was reproduced in the reviewed application contract. No critical, high, medium, or low contract-security finding is outstanding from this review.

The following properties were verified:

- Only the constructor's explicit owner can change the tracked collection. A factory deployment does not grant the factory authority. There is no transfer, renunciation, proxy, initializer, or upgrade path.
- Address validation requires code, canonical ERC-165 support, rejection of the invalid interface identifier, ERC-721 support, and a successful exactly 32-byte supply response. Noncanonical boolean values and short or overlong interface responses are rejected.
- Each supply read uses `STATICCALL` with a 100,000-gas budget. Only one 32-byte word can be copied into scratch memory, regardless of the callee's return-data size. Both success and exact return-data length are checked before using the word. Reverts, malformed replies, gas exhaustion, and attempted writes produce the specified zero-count fallback.
- Static restrictions propagate through callbacks. An adversarial collection that was also the machine's owner could not change configuration from inside a supply read. Recursive read callbacks remain bounded by the outer supply budget.
- Supply is clamped before it is used as a memory offset. Every whole-word write satisfies `cursor + 31 < end`; every remaining byte write satisfies `cursor < end`. Thus no write extends beyond the 10,000 payload bytes. The allocated black prefix and ABI padding remain zero.
- Pixel bytes are exactly `0x00` below the clamped count and `0xff` at and above it. Progress arithmetic is an identity for a 10,000-token target, avoiding rounding and multiplication overflow.
- The saved Vessel source forwards Machine payload requests using the implemented interface. Its renderer's 10,000-byte grid has 100 columns and 100 rows, places byte `i` at `(i % 100, i / 100)`, and maps grayscale mode 0 to `rgb(v,v,v)`. The integration suite explicitly checks mainnet code hashes, Machine type, grayscale mode, unlocked state, and absence of a Relic override before testing real Vessel attachment. It does not replace the deployed Vessel or renderer with a mock.

## Independently executed checks

Command:

```sh
forge test --match-path test/AdversarialReview.t.sol -vv
```

Result: **7 passed, 0 failed, 0 skipped**, using Solidity 0.8.26 and the pinned fuzz seed `0x70400acffe2a4602ecfd12d07e8d6076229abeecfafc6e78631ab193db2b3f92`.

The reviewer reran all seven tests after `dynamic_test_linking = false` was added to `foundry.toml`. This disables Foundry's test-only deployment shortcut, so the factory and owner-contract tests execute actual constructor bytecode. All seven passed again, including 256 fuzz cases and the unchanged malicious-call gas bounds. Reported whole-test gas was 911,817 for the factory-authority test and 1,116,012 for the owner-contract callback test; these totals include harness and mock deployments and are not standalone machine deployment estimates.

The suite included 256 fuzz cases checking every pixel and the exact raw ABI length and padding; every possible word alignment near both ends of the payload; malformed ERC-165 replies; 100 KB return and revert data; infinite-loop and state-writing supply contracts; a recursive read; an owner-contract callback; and factory ownership. Adversarial payload calls stayed below the test's 180,000-gas ceiling and the recursive count read stayed below 110,000 gas. These are bounded attack checks, not ordinary production gas benchmarks. The independent tests were developed in the reviewer's scratch directory and then promoted to the delivered `test/AdversarialReview.t.sol`.

An instruction-aware scan of the compiled runtime found no `DELEGATECALL`, `CALLCODE`, or `SELFDESTRUCT`. Runtime size was 1,384 bytes and the creation bytecode had no unresolved library links. The single nonpayable constructor argument is a static address; construction makes no external call and requires no deployed dependency.

The reviewer also ran `forge build` successfully. Forge emitted `warning[reentrancy-events]` for the update event following collection validation calls. This warning is a false positive for this implementation: every external validation is a bounded `STATICCALL`, so the callee and all its descendants are forbidden from updating storage or emitting logs. The adversarial owner-contract callback test confirms that even a callback satisfying the owner check cannot change configuration in this static execution context. The subsequent assignment and event execute only after validation has returned.

Slither, Mythril, formal verification, and a professional human audit were not performed. The reviewer did not sign or broadcast a transaction.

## Mainnet-fork evidence reviewed

The implementation runner recorded the following execution in `docs/results/mainnet-fork.txt`; the reviewer read its full result, the test source, the saved verified sources/ABIs, and the independently generated SVG oracle. This was an actual Ethereum mainnet fork at block **26,200,148**, not a local Vessel substitute.

```sh
FOUNDRY_PROFILE=mainnet FOUNDRY_FUZZ_SEED=0x70400acffe2a4602ecfd12d07e8d6076229abeecfafc6e78631ab193db2b3f92 forge test --fork-url https://ethereum-rpc.publicnode.com --fork-block-number 26200148 -vv
```

Result: **11 passed, 0 failed, 0 skipped**. The suite checked authorized and unauthorized attachment, default white rendering, live supply and collection changes through Vessel, burns, failed reads, and complete SVG hashes at counts 0, 1, 100, 101, 5,000, 9,999, and 10,000. The reviewer separately ran `python3 tools/svg_vectors.py` and verified that all seven output hashes and lengths match the integration fixtures.

The existing mainnet renderer consumed **422,513,100–470,553,365 gas** per measured full SVG call and produced **598,122–658,122 bytes**. This is a material external usability limitation: a normal RPC gas cap may reject full SVG or metadata calls even though the payload itself is efficient. The fork's ability to execute these large read calls does not establish that a public provider, Etherscan, or a marketplace accepts them, nor that rendering fits inside an Ethereum transaction. No change to the immutable machine can remove this cost in Vessel's existing renderer; modifying Vessel is outside the requested scope. The report therefore treats successful byte-level integration and public renderer availability as distinct conclusions.

## Trust assumptions and operational limits

- The launch must supply `$owner` as `0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a`. The constructor accepts an explicit nonzero address and cannot distinguish a mistaken nonzero deployment argument. The manifest and final deployed `owner()` value therefore need deployment-stage verification.
- ERC-165 checks establish interface claims, not truthfulness. The selected collection can report an arbitrary supply, change implementation, or change read behavior. The machine deliberately uses the current reported outstanding supply. Burns may reverse progress.
- A collection whose `totalSupply()` requires more than 100,000 gas, has a nonstandard return shape, or temporarily fails cannot supply a usable count. The rendered fallback is white and is indistinguishable from a genuine zero supply in the image. The owner may select a compatible collection without replacing the machine.
- Ownership is deliberately immutable. Loss of the specified owner's signing capability would prevent future configuration changes. This is a consequence of the requested no-transfer design, not an extra privilege or an implementation defect.
- The machine controls neither The Vessel nor Craft #10000. Attachment must be authorized by The Vessel's current Craft permissions and remains an explicit owner operation after deployment.
- Vessel administration and dependencies remain external trust assumptions. A renderer change, color-mode change, or Relic override can affect the displayed result independently of the machine. Full SVG rendering uses the existing renderer and can cost much more gas than generating the 10,000-byte payload; the two costs must be reported separately.

## Release evidence boundary

The final application source was reread after implementation completion and the independent adversarial suite was rerun successfully. Required mainnet-fork integration has passed in the reviewed evidence. Final deployment attestation, mainnet transaction confirmation, explorer verification, and repository publication remain separate launch-stage deliverables; this report does not claim that any of them occurred. Historical fork assertions must be rechecked before attachment because the live Craft state and external Vessel dependencies can change.
