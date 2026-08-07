# Architecture

## Design objective

The prototype projects a constrained ODRL policy into values that are inexpensive to evaluate on an EVM chain while retaining a hash and URI for the full off-chain policy. It evaluates two independent sources of authority: platform entitlements and asset-owner policy.

## Components

| Component | State authority | Responsibility |
|---|---|---|
| `UserRegistry` | Platform administrator | Maps an Ethereum address to a user identifier, group, and active status. |
| `PlatformEntitlementRegistry` | Platform administrator | Stores the platform action mask for each user-group and asset-type pair. |
| `AssetPolicyRegistry` | Asset owner; administrator can transfer only its own admin role | Registers assets and stores group-indexed permission/prohibition masks, validity, policy hash, and URI. |
| `AuthorizationAndLicenseRegistry` | Authorized orchestrators issue licenses; administrator manages orchestrators | Intersects the other registries' decisions and records successful authorizations. |
| `odrl_compiler.py` | Off-chain operator | Converts the supported ODRL subset into deterministic hashes, IDs, masks, and call arguments. |

## Authorization decision

For a user `u`, asset `a`, and a single action bit `x`, authorization succeeds only when all of the following hold:

```text
activeUser(u)
AND activeAsset(a)
AND activeAndCurrentlyValidPolicy(a)
AND platformMask[group(u), type(a)] contains x
AND assetPermissionMask[a, group(u)] contains x
AND assetProhibitionMask[a, group(u)] does not contain x
```

The read-only `checkAuthorization` function returns a Boolean and a `DenialReason`. `authorizeAndIssueLicense` repeats the checks, rejects duplicate request IDs, creates a deterministic license ID from request context and chain context, stores the license, and emits `LicenseIssued`.

## Data representation

### Action masks

Each supported action occupies one bit (`1`, `2`, or `4`). Several permitted actions can be stored in one mask. Prohibition takes precedence in the asset registry:

```text
effectiveMask = permissionMask & ~prohibitionMask
```

The contracts validate stored masks against the three supported bits. An authorization request must select exactly one bit, preventing ambiguous multi-action requests.

### Identity and integrity

- `assetId`: Ethereum Keccak-256 of the UTF-8 ODRL target string in compiler-generated examples.
- `policyHash`: Ethereum Keccak-256 of the compiler's canonical JSON representation.
- `metadataHash`: supplied when an asset is registered; its canonicalization is application-defined and outside this compiler.
- `userId`: application-supplied `bytes32` identifier linked to an Ethereum address.

Consumers must use the same canonicalization procedure when checking a stored hash. Ethereum Keccak-256 is not the standardized SHA3-256 function.

## Lifecycle and versioning

Entitlements and asset policies start at version 1. Updating a mask or policy increments its version. Issued licenses snapshot the asset-policy and entitlement versions used for the decision. Later policy changes do not modify historical license records.

Asset policies can be bounded by `validFrom` and `validUntil`; zero means no lower or upper bound, respectively. A license's `validUntil` is copied from the asset policy. Deactivating a user, asset, entitlement, or policy affects subsequent checks but does not erase issued records.

## Trust and threat model

The platform administrator is trusted to manage users, platform entitlements, and authorized orchestrators correctly. Asset owners are trusted to publish authentic policies and metadata for assets they register. Orchestrators are trusted to submit genuine request IDs and bind on-chain authorization to the off-chain service request.

The design provides deterministic policy projection, on-chain decision transparency, duplicate-request protection, and historical evidence. It does not establish off-chain identity, guarantee URI availability, validate the semantics of content behind a URI, protect administrator keys, or enforce use of an asset after a license is issued.

