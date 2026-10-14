# BLOX IMD (BLOX)

A fixed-supply ERC-20 built with OpenZeppelin Contracts v5.4.0. The complete
production contract is [`src/BLOXToken.sol`](src/BLOXToken.sol).

| Parameter | Value |
| --- | --- |
| Solidity contract | `BLOXToken` |
| Token name | `BLOX IMD` |
| Symbol | `BLOX` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` ETH |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | None |

## Behavior and assumptions

The constructor mints the entire supply exactly once and emits the standard
`Transfer` event from the zero address. The token uses the inherited 18 decimals.
No external function can mint or burn, so `totalSupply()` remains constant.

Transfers and delegated transfers move the exact requested amount. There are no
token taxes, fees, rebases, wallet limits, trading gates, blacklists, pauses,
owner roles, upgrades, initialization calls, or external service dependencies.
No application contracts are needed for this token. The contract makes no
external calls during construction or transfers.

The ERC-20 behavior is unchanged from the vendored OpenZeppelin implementation:

- `transfer`, `approve`, and `transferFrom` return `true` on success. Invalid
  operations revert with ERC-6093 custom errors.
- Zero-value transfers and self-transfers are valid. Transfers to the zero
  address and approvals for the zero address are rejected.
- `approve` replaces an allowance. The holder can revoke it with
  `approve(spender, 0)`. Finite allowances decrease when spent; the maximum
  `uint256` allowance remains unchanged until replaced or revoked.
- Transfers emit `Transfer`; explicit approvals emit `Approval`. As in
  OpenZeppelin v5, spending an allowance does not emit an additional `Approval`.
- Even the deployer must obtain an allowance to spend another holder's tokens.

Use token amounts in smallest units: one BLOX is `10^18` units. Unlimited
approval grants continuing spending authority. Holders should approve only what
they intend to spend; changing a live nonzero allowance has the usual ERC-20
transaction-ordering race. Revoke first and wait for confirmation before granting
a replacement allowance when this matters.

## Build and check

From the repository root, with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x80d3b502b8a696711c1c85a60a41e55903c33d2c81e1671b3305f4203c5d3a83 forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`.
See [`lib/README.md`](lib/README.md) for exact versions, source URLs, and archive
hashes. Builds need no dependency installation, Git submodules, RPC connection,
keys, FFI, or filesystem cheatcode permissions. The compiler is pinned by
version, and the verifier supplies that compiler offline.

The tests cover metadata, the one-time mint event, direct and CREATE2 factory
deployment, exact distribution and pool-address transfers, approval replacement
and revocation, delegated spending, unlimited allowances, zero values,
self-transfers, and failure atomicity. They probe unsupported administrative,
minting, burning, and upgrade entry points from both the deployer and a stranger.
Four parameterized fuzz tests run 1,000 cases each; two stateful invariants run
128 histories of up to 64 operations, checking independently modeled balances
and allowances and conservation of the whole supply.

Tests create fresh state, use deterministic local actors, and do not read or
change environment variables. They work without a fork, in parallel, and in
any order. Test addresses and `TokenFactoryProbe` are fixtures, not deployment
parameters or production contracts.

The supplied protected tests were read as acceptance definitions. They depend on
the network's separate launch harness, manifest environment, and Uniswap v4
contracts, which are not included in the provided inputs. The local launch-flow
test verifies exact token movements; it does not claim to execute a real AMM
swap. The network verifier performs that integration check.

## Deployment and operational responsibilities

The deployable artifact is `out/BLOXToken.sol/BLOXToken.json`. Deploy its creation
bytecode with no appended constructor arguments and no ETH. There are no linked
libraries or post-deployment initialization calls. The constructor requires no
other deployed contracts and works on an empty chain.

The immediate contract creator receives all tokens. Under the assigned Ethereum
launch flow, that creator is the launch factory, which distributes the supply.
Deploying through a different helper would instead give that helper all tokens;
the transaction origin is never used. There is no owner address to configure or
privilege to transfer or renounce.

The separate launch service is responsible for the manifest, factory deployment,
allocation, pool creation, source verification, and checking the deployed
metadata, bytecode and supply. This project neither creates `launch.json` nor
broadcasts transactions. The launch parameters supplied with the assignment,
for that service rather than the token constructor, are:

| Launch setting | Assigned value |
| --- | --- |
| Chain | Ethereum, chain ID `1` |
| Paired currency | IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Pool fee / tick spacing | `12500` (1.25%) / `60` |
| Pool initial-price provenance | `79228162514264337593543950336`; actual opening price is derived by the deployer |
| Swarm allocation | 10%, transferred by the factory to its MerkleDistributor |
| Pool allocation | `poolBps = 8800` (88%) |
| Initial market cap | `initialMarketCapWei = "2500000000000000000000"` (2,500 IMD) |
| Remainder allocation | 2% to `0x0f44a55663e888bb63618a0c31b68cbc6c01aa71` |

These values are not embedded in the token and do not cause constructor
transfers. All `10^27` units first belong to the deploying factory.

### After launch

No configuration, owner setters, keepers, or ongoing operator actions are
required. Holders manage their keys, transfers, and allowances. There is no
recovery or rescue function: tokens sent to this token contract or to an
inaccessible address cannot be recovered by an administrator, and ordinary
native-ETH transfers to the token revert.

The source and vendored ERC-20 were reviewed against the provided security
reference for supply changes, access control, arithmetic, allowance handling,
external calls, and deployment assumptions. Foundry build, unit/fuzz/invariant
tests, and formatting are the local verification tools. Slither and Mythril
were not run. Independent adversarial review and the launch integration checks
remain the network's release responsibilities; local tests are not an audit.
