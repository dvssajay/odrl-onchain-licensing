# Deployment and initialization

This guide describes a manual prototype deployment, suitable for reproduction in Remix or an equivalent Solidity environment. Use the same administrator account for the first three contracts unless intentionally testing separated administration.

## 1. Compile

Compile all files in `contracts/` with a compiler compatible with Solidity `^0.8.24`. Optimizer settings and target EVM version should be recorded with experimental results because they affect deployment bytecode and gas measurements.

## 2. Deploy in dependency order

1. Deploy `UserRegistry` (no constructor arguments).
2. Deploy `PlatformEntitlementRegistry` (no constructor arguments).
3. Deploy `AssetPolicyRegistry` (no constructor arguments).
4. Deploy `AuthorizationAndLicenseRegistry` with the addresses from steps 1–3, in that order.

The deployer becomes `platformAdmin` in each contract. The fourth contract also authorizes its deployer as an orchestrator.

## 3. Configure platform state

Register a user with `UserRegistry.registerUser(userAddress, userId, group)`. Then create the platform entitlement using the compiler output:

```text
PlatformEntitlementRegistry.createEntitlement(group, assetType, actionMask)
```

For `User_dAIedge.json`, the reference values are `(1, 1, 7)`.

## 4. Register an asset and policy

Use the asset owner's account to call:

```text
AssetPolicyRegistry.registerAsset(assetId, assetType, metadataHash, metadataURI)
AssetPolicyRegistry.createPolicy(
    assetId,
    policyHash,
    policyURI,
    permissionMasks,
    prohibitionMasks,
    validFrom,
    validUntil
)
```

The compiler supplies all policy arguments and `assetId`. `metadataHash` and `metadataURI` describe the asset rather than its ODRL policy and must be prepared separately. A nonzero `metadataHash` is required.

## 5. Check and issue

Any caller can preview a decision:

```text
AuthorizationAndLicenseRegistry.checkAuthorization(user, assetId, actionBit)
```

An authorized orchestrator can issue a license:

```text
AuthorizationAndLicenseRegistry.authorizeAndIssueLicense(
    requestId,
    user,
    assetId,
    actionBit
)
```

`requestId` and `assetId` must be nonzero `bytes32` values. `actionBit` must be exactly `1`, `2`, or `4`, not a combined mask. Reusing a request ID is rejected.

## 6. Verify the record

Retrieve the license with `getLicense(licenseId)` or `getLicenseByRequest(requestId)` and retain the `LicenseIssued` event in the experiment log. Record chain ID, contract addresses, transaction hashes, compiler version/settings, input policy digest, and deployed source revision.

## Operational cautions

- Transfer each administrator role only to a checked, nonzero address. Transfers are immediate and use a one-step process.
- Asset ownership transfer delegates future policy administration for that asset.
- Policy and entitlement updates increment versions; report the versions used in each experiment.
- Store durable content at `policyURI` and `metadataURI`; the contracts do not guarantee availability.
- Use unique request IDs derived from the surrounding application workflow.

