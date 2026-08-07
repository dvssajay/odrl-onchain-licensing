# ODRL On-Chain Licensing Prototype

Research prototype accompanying a paper on translating selected Open Digital Rights Language (ODRL) policies into compact, on-chain authorization rules. The repository contains a deterministic Python compiler, four Solidity registries, and two reproducible input/output examples.

> **Prototype status:** This code is intended for research evaluation. It has not been independently audited and must not be used to protect production assets or funds without further testing and security review.

## What is included

```text
.
├── contracts/                    Solidity 0.8.24 contracts
│   ├── UserRegistry.sol
│   ├── PlatformEntitlementRegistry.sol
│   ├── AssetPolicyRegistry.sol
│   └── AuthorizationAndLicenseRegistry.sol
├── compiler/
│   ├── odrl_compiler.py          ODRL-to-contract argument compiler
│   ├── requirements.txt
│   └── examples/                 Source policies and expected outputs
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT.md
│   ├── POLICY_COMPILER.md
│   └── REPRODUCIBILITY.md
├── tests/                        Compiler regression tests
├── CITATION.cff
├── LICENSE
└── SECURITY.md
```

## System overview

The prototype separates policy administration from authorization:

1. `UserRegistry` assigns an active user to one of four groups.
2. `PlatformEntitlementRegistry` records the actions the platform allows for each `(user group, asset type)` pair.
3. `AssetPolicyRegistry` stores asset metadata and the asset owner's permission and prohibition masks.
4. `AuthorizationAndLicenseRegistry` permits an action only when the user, platform entitlement, asset, and asset policy all allow it. An authorized orchestrator can then issue an immutable license record for that request.

The compiler keeps the complete ODRL JSON off-chain and emits hashes, identifiers, and action masks suitable for the registries. See [Architecture](docs/ARCHITECTURE.md) and [Policy compiler](docs/POLICY_COMPILER.md).

## Encodings

| Concept | Values |
|---|---|
| User group | `1=dAIEdge`, `2=NoE`, `3=AIoD`, `4=Other` |
| Asset type | `1=Hardware`, `2=Dataset`, `3=AIModel` |
| Action bits | `TYPE1=1`, `TYPE2=2`, `TYPE3=4` |

For datasets and AI models, the same bit positions have domain aliases described in [Policy compiler](docs/POLICY_COMPILER.md). Combined permissions use bitwise OR; authorization requests must contain exactly one action bit.

## Quick start

Requirements: Python 3.9 or later and Solidity compiler 0.8.24 or a compatible `0.8.x` compiler accepted by `pragma ^0.8.24`.

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r compiler/requirements.txt
```

Compile the included asset policy:

```bash
python3 compiler/odrl_compiler.py \
  compiler/examples/H9_Policy.json \
  --kind asset \
  --asset-type hardware \
  --policy-uri "ipfs://replace-with-real-cid" \
  --output /tmp/H9_Policy.onchain.json
```

Compile the included platform entitlement:

```bash
python3 compiler/odrl_compiler.py \
  compiler/examples/User_dAIedge.json \
  --kind entitlement \
  --asset-type hardware \
  --output /tmp/User_dAIedge.onchain.json
```

Run the regression tests:

```bash
python3 -m unittest discover -s tests -v
```

The committed `.onchain.json` files are reference outputs. See [Reproducibility](docs/REPRODUCIBILITY.md) for exact verification commands and [Deployment](docs/DEPLOYMENT.md) for contract deployment and initialization.

## Scope and limitations

- The compiler supports the policy subset documented in `docs/POLICY_COMPILER.md`; it is not a general ODRL implementation.
- Policies and metadata remain off-chain. The contracts store integrity hashes, URIs, masks, validity intervals, and version data.
- Contract administration uses single privileged addresses rather than multisignature or role-based governance.
- The prototype has no upgrade mechanism, automated deployment scripts, full Solidity test suite, or external security audit.
- A generated license is an authorization evidence record; it does not transfer legal ownership or replace the referenced legal terms.

## License and citation

The code is released under the [MIT License](LICENSE). Citation metadata is provided in [CITATION.cff](CITATION.cff); replace its placeholder author and paper fields before archival publication.

