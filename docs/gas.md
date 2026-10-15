# Gas benchmarks

Measured with Foundry 1.8.3, Solidity 0.8.26, Cancun target, optimizer enabled at 200 runs, metadata bytecode hash `none`, and `dynamic_test_linking = false`. The supply fixture is a test-only contract with storage-backed `totalSupply()`; a real collection's read cost will differ within the fixed 100,000-gas allowance.

Commands and complete output are in [verification.md](verification.md), [unit-tests.txt](results/unit-tests.txt), and [mainnet-fork.txt](results/mainnet-fork.txt).

## Payload generation

`test/Gas.t.sol` explicitly cools the Machine and collection before each direct call. The full-call column measures `gasleft()` around the external call, including call overhead, return copying, and caller ABI decoding. The callee-only column comes from Foundry's last-call gas measurement. These exclude Ethereum transaction intrinsic gas and gas-price-dependent fees.

The Vessel column measures its real `craftToPayload(10000)` execution on the fork with warmed routing state. Its nested Machine read is included. Callee measurements avoid the increasing caller-memory overhead of a loop that retains multiple 10,000-byte results.

| Outstanding supply | Direct Machine execution, cold | Direct call including caller decoding, cold | Through Vessel execution, warm |
| ---: | ---: | ---: | ---: |
| 0 | 37,669 | 45,553 | 68,713 |
| 1 | 37,609 | 45,493 | 68,653 |
| 100 | 37,222 | 45,106 | 68,266 |
| 101 | 37,162 | 45,046 | 68,206 |
| 5,000 | 26,425 | 34,309 | 57,469 |
| 9,999 | 15,241 | 23,125 | 46,285 |
| 10,000 | 15,181 | 23,065 | 46,225 |

The buffer is allocated once. Solidity zero-initializes the black prefix; the white suffix is filled using at most 312 word stores and 31 byte stores. No pixel state is written to storage. A single bounded supply read is made for each payload. The worst successful-case direct call is comfortably below the test's 60,000-gas regression ceiling for this fixture.

A collection that runs forever consumes its 100,000-gas supply budget and produces a white payload. The measured cold full-call cost was **140,599 gas**, below the tested 160,000 ceiling. Independent return/revert-bomb and recursive-callback tests also pass their gas bounds. These ceilings are test conditions with an adequate outer call budget, not a promise that a deliberately underfunded outer call can never run out of gas.

## Deployment and collection configuration

| Operation | Measured gas | Measurement scope |
| --- | ---: | --- |
| `new SelloutMachine(owner)` | 387,288 | `gasleft()` around CREATE, including creation overhead; no enclosing transaction intrinsic gas |
| First collection selection | 56,739 | Cold external setter call, including interface/supply validation and event |
| Replace selected collection | 42,156 | Cold external setter call, including validation and event |
| Fork attachment plus routing assertion | 70,904 | Test helper including actual Vessel `setMachineHolder` and subsequent `craftToMachine` check |

Runtime is **1,384 bytes**. Creation bytecode is **1,555 bytes**, or 1,587 bytes with the 32-byte constructor argument. The runtime is well below EIP-170's 24,576-byte limit; there are no external library links.

Factory deployment transaction gas will also include IMD's factory/attestation work, CREATE2 hashing, calldata and transaction overhead. It is not represented by the standalone CREATE measurement. The aggregate Forge gas report includes failing/adversarial calls and uses different measurement boundaries; its averages are not normal-operation quotations.

## Existing Vessel SVG renderer

These calls executed the deployed Vessel and its actual renderer at mainnet block **26,200,148**, after an authorized attachment on the local fork. The entire returned SVG was checked against the independent Python oracle, including every pixel position and RGB value.

| Black pixels | Full Vessel SVG call gas | SVG bytes |
| ---: | ---: | ---: |
| 0 | 470,553,365 | 658,122 |
| 1 | 470,548,823 | 658,116 |
| 100 | 470,071,349 | 657,522 |
| 101 | 470,066,807 | 657,516 |
| 5,000 | 446,508,347 | 628,122 |
| 9,999 | 422,517,642 | 598,128 |
| 10,000 | 422,513,100 | 598,122 |

The renderer builds 10,000 individual SVG rectangles and copies many string bytes. Its cost dominates the Machine's inexpensive payload generation. The block gas limit at the pinned block was 60,000,000, below these full-render costs. These images can be evaluated as view calls with sufficient RPC allowances; they cannot fit into an ordinary transaction under that block gas limit. Many public RPCs impose lower view-call gas caps, and token metadata also uses the renderer. The successful fork suite uses Foundry's large call allowance and does **not** prove that every public RPC or marketplace can retrieve the full SVG.

The Vessel and renderer were not modified or redeployed. The payload is compact and cheap to read directly. Rendering-service compatibility remains an external operational constraint of the existing Vessel deployment.
