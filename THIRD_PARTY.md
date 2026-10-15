# Third-party material

## forge-std

Test dependency only, vendored from [foundry-rs/forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7). `lib/forge-std/src/` contains ordinary source files. The upstream MIT and Apache-2.0 licenses are preserved as `lib/forge-std/LICENSE-MIT` and `lib/forge-std/LICENSE-APACHE`. No submodule or package manager is required.

## The Vessel

The ABI definitions and source snapshots under `docs/reference/` were obtained from the [verified Vessel contract](https://eth.blockscout.com/address/0xECb92Cc7112b80A2234936315BbB493fb48d1463?tab=contract) and [verified renderer](https://eth.blockscout.com/address/0x85c7D2933f178A02Ee9AAC0E654094EaDAca48a2?tab=contract). Both source files declare MIT and match [producedbydav/The-Vessel at b0cbb6c89f8c051648bdc2cd3df9ed05b5295e32](https://github.com/producedbydav/The-Vessel/tree/b0cbb6c89f8c051648bdc2cd3df9ed05b5295e32) after trimming trailing whitespace.

These are read-only evidence snapshots, not build dependencies or application contracts to deploy. The application implements the two-function IMachine ABI shown by the [official Machine documentation](https://www.thevessel.fun/docs/machines). The independently written Python SVG oracle follows the verified renderer's output format.
