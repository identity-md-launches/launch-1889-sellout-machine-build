# IMD deployment handoff and owner operations

## Deployment parameters

Deploy **one** application, `SelloutMachine`, from `src/SelloutMachine.sol`, through IMD's contracts-only Ethereum mainnet launch system. Do not deploy any contracts from `test/`, `integration/`, or the reference snapshots.

| Parameter | Required value |
| --- | --- |
| Chain ID | 1 |
| Solidity compiler | 0.8.26 |
| EVM target | cancun |
| Optimizer | enabled, 200 runs |
| via IR | disabled |
| Metadata bytecode hash | none |
| Constructor | `constructor(address owner_)` |
| Constructor argument source | IMD `$owner` |
| Resolved constructor address | `0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a` |
| Constructor ABI word | `000000000000000000000000ccf0a1307e5e5ad04e85d94d7f9d400390f0118a` |
| Deployment ETH | 0 |
| Initial tracked collection | unset intentionally |
| Initialization calls | none |
| Token / pool / proxy | none |
| Linked external libraries | none |

The application has a single static constructor argument and no external constructor calls. Its owner does not derive from `msg.sender` or `tx.origin`. The constructor works when no other contracts exist on the deployment-check chain. The build uses the root `foundry.toml`; do not substitute optimizer, metadata, compiler, or EVM settings when verifying it.

The subsequent IMD manifest step supplies `$owner`. This assignment does not create `launch.json`, call the factory, read a signing key, broadcast a transaction, or initialize a deployed application. IMD should deploy only after required checks and review succeed, verify the source and exact constructor argument on Etherscan, and record the confirmed mainnet transaction and address. The owner is immutable, so the launch must verify the constructor argument before deployment and `owner()` afterward.

The Machine is usable immediately after deployment: `name()` is `The Sellout Machine`, `mintedCount()` and `mintProgress()` are zero, `trackedCollection()` is unset, and `craftToPayload(10000)` is 10,000 white bytes. No post-deployment initialization by IMD workers is needed. Collection choice and Craft attachment are later user operations expressly requested in the brief.

## Release receipt

| Requested receipt item | Status at this assignment |
| --- | --- |
| Source and Foundry tests | Delivered in this repository |
| Successful build / tests / format | Recorded in [verification.md](verification.md) |
| Independent adversarial review | Complete; [security-review.md](security-review.md) |
| Actual mainnet-fork integration | 11 passed, no failures or skips |
| Mainnet contract address | Pending IMD deployment |
| Mainnet deployment transaction | Pending IMD deployment |
| Etherscan source verification | Pending IMD deployment/verification |
| Published GitHub repository and commit | Pending contributor-network publication |
| Mainnet Craft attachment | Intentionally left for the Craft holder |

No address, transaction, or commit has been invented. The task forbids touching `.git/`; repository publication and the accepted commit are owned by the submission pipeline. The public Vessel repository is an upstream reference, not this application's publication destination. The final launch receipt must provide the actual repository/commit, Etherscan contract link, transaction hash, chain ID, resolved owner, and verification status before representing the application as deployed.

## Attach the Machine to Craft #10000

Use the **confirmed deployed Machine address from IMD's receipt**. Do not use a fork-test address. This process is manual; the build and deployer do not attach it automatically.

1. Open [The Vessel on Etherscan](https://etherscan.io/address/0xECb92Cc7112b80A2234936315BbB493fb48d1463#readContract). On Ethereum mainnet, read `ownerOf(10000)`, `craftToMachineStatus(10000)`, `craftToLocked(10000)`, and `craftToColorMode(10000)`. The Machine requires Machine type, an unlocked attachment, and grayscale mode 0 for the documented appearance. A Relic override must also be absent. These held at the tested block; check current state before sending.
2. In Vessel's **Contract → Write Contract**, use **Connect to Web3** with Craft #10000's current holder or its Vessel-appointed delegate. A normal ERC-721 approved operator alone is not accepted by `setMachineHolder`; Vessel specifically checks holder/delegate. At the tested block the holder was the requested wallet.
3. Call **`setMachineHolder`** with `_tokenId = 10000` and `_machine =` the confirmed Machine address. Send zero ETH and pay normal Ethereum transaction gas.
4. After confirmation, read `craftToMachine(10000)` and verify it equals that address. `MachineSet` and `MetadataUpdate` are emitted by Vessel. `craftToPayload(10000)` should return exactly 10,000 bytes. If no collection has been selected, all are `ff`.

Vessel's web [Assembly interface](https://www.thevessel.fun/assembly) can also be used if it exposes a custom Machine address field. The verified `setMachineHolder` ABI above is the definitive operation.

Full `craftToSVG(10000)` and `tokenURI(10000)` reads inherit Vessel's expensive renderer and can exceed a provider's `eth_call` gas cap. Use a provider with a sufficient view-call allowance when checking the complete SVG; direct payload reads are much cheaper. Fork success does not certify a marketplace's cache or RPC limit.

## Choose or change the collection through Etherscan

1. Obtain the intended NFT collection's Ethereum mainnet contract address from its official project/explorer records. It must satisfy the [collection requirements](../README.md#collection-requirements-and-failure-policy). A website, marketplace page, token ID, wallet address, or ERC-20 address is not a collection contract.
2. Open the deployed **SelloutMachine** contract's Etherscan page from IMD's receipt. Confirm source verification and, under **Read Contract**, check `owner()` equals `0xCcf0a1307E5e5Ad04E85d94d7f9D400390F0118a`.
3. Under **Contract → Write Contract → Connect to Web3**, connect that owner wallet on Ethereum mainnet. Select **`setTrackedCollection`**, enter the NFT contract in `newCollection`, and submit with zero ETH.
4. After confirmation, check `TrackedCollectionUpdated(previousCollection, newCollection)`, `trackedCollection()`, `mintedCount()`, and `mintProgress()`. The last two return the same integer here because one token equals one basis point. For example, 5,000 means 50%.
5. Repeat this setter whenever the collection should change. **No redeployment or Craft reattachment is needed.** Only the collection address changes; the Craft still points to the same Machine.

An incompatible selection reverts atomically. If a selected contract later fails supply reads, the display falls back to white until it recovers or the owner selects another compatible collection. Burns may turn black pixels white. The owner should use a collection whose intended outstanding-supply target is 10,000; this Machine always clamps at that target regardless of the collection's own maximum.

Dynamic reads do not emit per-mint events from the Machine. A marketplace may need its metadata cache refreshed. Vessel's public `refreshMetadata(10000)` can emit its metadata update event if needed; it is optional and is not required to update the payload itself.

## Operational responsibilities

- **IMD:** final manifest/attestation, deployment, receipt, explorer verification, and source/commit publication. Verify the exact owner and runtime; do not attach or initialize the Machine.
- **Craft holder/delegate:** authorize the one-time Vessel attachment while its rules permit it.
- **Machine owner:** select the intended compatible collection and retain signing access. The no-transfer design intentionally has no recovery administrator.
- **Viewers/integrators:** query the desired block and allow sufficient RPC gas for the external renderer; distinguish live supply from cached images.
