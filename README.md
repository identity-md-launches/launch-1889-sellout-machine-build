# The Sellout Machine

A standalone, immutable Solidity Machine for **The Vessel Craft #10000** on Ethereum mainnet. Each read produces exactly 10,000 grayscale bytes representing the current outstanding supply of an owner-selected ERC-721 collection.

**Implementation and tests are complete; mainnet deployment, explorer verification, and GitHub publication are subsequent IMD launch steps.** No production address, transaction hash, or published commit is claimed by this build. Nothing has been attached to Craft #10000 on mainnet.

## Behavior

Pixel `i` is black (`0x00`) when `i < min(totalSupply(), 10000)`, otherwise white (`0xff`). Vessel's grayscale renderer places it at `x = i % 100`, `y = i / 100`. At supply 100 the first row is black; at 101 the second row's first pixel is black; at 9,999 only the bottom-right pixel remains white.

The constructor leaves `trackedCollection` unset and the image completely white. This unset state is intentional and requires no worker initialization. The authorized owner can select or replace the collection at any time. The attachment remains the same.

There is no backend, keeper, oracle, per-mint Machine transaction, stored pixel array, token launch, payment mechanism, proxy, or upgrade path. Reads reflect supply at the queried block. **Burns may reduce `totalSupply()` and reverse pixel progress.** This is not a lifetime-mint counter. Display services may cache images even though onchain reads are dynamic.

## Owner and deployment

| Setting | Value |
| --- | --- |
| Network | Ethereum mainnet, chain ID 1 |
| Application | `src/SelloutMachine.sol:SelloutMachine` |
| Constructor | `constructor(address owner_)`, nonpayable |
| IMD constructor argument | `$owner` |
| Resolved owner | `0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a` |
| Vessel | `0xECb92Cc7112b80A2234936315BbB493fb48d1463` |
| Craft ID / capacity | 10000 / 10,000 bytes |
| Initial collection | Unset by design; no collection argument |

The owner is immutable and comes only from the constructor argument. The deploying factory and transaction origin receive no authority. There is no ownership transfer or renunciation function. The single owner-only function is `setTrackedCollection(address)`.

The constructor calls no external contract and works on an empty chain. Deploy only this application contract with zero ETH. `launch.json` is reserved for IMD's subsequent manifest step and is deliberately absent. See [deployment and owner operations](docs/deployment.md) for the full handoff and Etherscan instructions.

## Collection requirements and failure policy

The owner must select a deployed Ethereum ERC-721 contract that:

- Supports ERC-165 (`0x01ffc9a7`) and ERC-721 (`0x80ac58cd`), and rejects invalid interface `0xffffffff`.
- Returns canonical 32-byte booleans from `supportsInterface(bytes4)` within 30,000 gas per call.
- Exposes `totalSupply()` returning exactly one ABI-encoded `uint256` within **100,000 gas**.

`totalSupply()` is optional in basic ERC-721; an otherwise valid NFT without that method is incompatible. The Machine does not require the entire ERC-721 Enumerable extension. ERC-20s and supply-only contracts are rejected by the interface checks. ERC-165 claims cannot prove a collection is honest; the owner is responsible for selecting the intended NFT contract.

Zero addresses, EOAs, missing code, failed interface checks, and invalid supply responses revert with `InvalidCollection(address)`. A failed selection leaves the previous collection unchanged. Successful selections emit `TrackedCollectionUpdated(previousCollection, newCollection)`, including a repeated selection of the same address. Clearing a configured collection to zero is not supported.

If a previously selected collection later reverts, exceeds the supply call budget, attempts a state change, loses its code, or returns a short/overlong response, the read returns zero and the image is white. A successful later read automatically recovers. The image cannot distinguish an unavailable supply from genuine zero supply. Only 32 bytes of return data are copied, including when a hostile contract returns much more.

The supply gas cap and capacity are public constants, not admin settings. `mintProgress()` is basis points (0–10000): each token in a 10,000-token target is exactly one basis point.

## Build and test offline

Foundry and Solidity **0.8.26** are the only build tools required. `forge-std` v1.9.7 is vendored as ordinary source files under `lib/forge-std`; there are no submodules or network-fetched build dependencies. The verifier supplies the pinned compiler.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x70400acffe2a4602ecfd12d07e8d6076229abeecfafc6e78631ab193db2b3f92 forge test
forge fmt --check
```

The default tests run offline and do not read or set environment variables. The same seed is pinned in `foundry.toml`. Tests cover every requested milestone, all byte positions, clamping, live mint/burn changes, factory ownership, unauthorized calls, bad interfaces, malformed replies, gas/return-data attacks, static callbacks, recursive reads, raw ABI padding, and gas ceilings.

## Actual mainnet-fork integration

```sh
FOUNDRY_PROFILE=mainnet forge test \
  --fork-url https://ethereum-rpc.publicnode.com \
  --fork-block-number 26200148 -vv
```

The `mainnet` profile runs `integration/`, requires a real fork, and fails if its mainnet/block/code/state preconditions are absent. It does not silently skip. The separate default suite stays usable in the offline verifier. An archive-capable Ethereum RPC can replace the public URL.

**11 fork tests passed, with no failures or skips.** They call the actual Vessel contract, impersonate the actual Craft holder only within the fork, attach the newly deployed Machine, read its payload through Vessel, reject unauthorized attachment, change collections without reattachment, and compare every byte of seven rendered SVGs with an independently generated oracle. Neither Vessel nor its renderer is replaced or modified. The tracked supply is a controllable test mock on the fork; this does not attest any future owner-selected collection.

**External rendering limit:** Vessel's existing SVG renderer used approximately **422–471 million gas** for these 10,000-pixel images. Fork execution succeeds with Foundry's large view-call budget. Many RPC services impose lower `eth_call` gas limits, so full SVG/metadata reads may fail there; the fork results do not establish availability on every marketplace or RPC. Direct Machine payload generation measured about **23,000–46,000 gas including caller decoding**. This project does not change Vessel's renderer. See [gas measurements](docs/gas.md) and [verification evidence](docs/verification.md).

## After launch

1. IMD confirms the mainnet deployment, verifies source on Etherscan, and publishes the repository/commit and deployment receipt. Verify the resulting `owner()` equals the wallet above and that `trackedCollection()` is initially unset.
2. The Craft holder attaches the deployed Machine using Vessel's `setMachineHolder(10000, machineAddress)`. This is an explicit owner operation; this project does not automatically attach it.
3. The Machine owner calls `setTrackedCollection(collectionAddress)` using the intended collection's official mainnet contract address. No initial collection was specified in the brief, so none is guessed or preconfigured. This can happen before or after attachment and can be repeated later.

Only the holder/delegate authorized by Vessel can attach the Machine; owning this Machine's configuration role does not bypass Craft permissions or locks. Collection configuration remains possible even if Vessel later locks the attachment.

## Review and provenance

An independent AI reviewer performed an adversarial review and added the permanent [adversarial tests](test/AdversarialReview.t.sol). No exploitable contract defect was reproduced. See the [review report](docs/security-review.md) for scope, evidence, and limitations; this is not a professional human audit.

The deployed Vessel ABI, verified sources, renderer, code hashes, upstream commit, and mainnet state used for compatibility checks are recorded under [docs/reference](docs/reference/provenance.json). See [third-party dependencies](THIRD_PARTY.md).
