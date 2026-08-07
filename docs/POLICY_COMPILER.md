# Policy compiler

## Purpose

`compiler/odrl_compiler.py` converts a documented subset of ODRL JSON into arguments for `PlatformEntitlementRegistry` or `AssetPolicyRegistry`. It performs no deployment or network access.

## Supported policy shapes

### Platform entitlement

A top-level `constraint` must resolve to exactly one group using `leftOperand` `userGroup` or `group`. Actions are collected from `permission` rules. The output contains `group`, `assetType`, and the combined `actionMask`.

### Asset policy

Each `permission` or `prohibition` rule must have a group constraint (`allowedUserGroups`, `userGroup`, or `group`). Masks are accumulated independently for four groups. The output contains the asset ID, policy hash and URI, permission/prohibition arrays, and validity interval.

The group-array order is fixed: indexes `0..3` correspond to `Group1..Group4`.

## Mappings

| Canonical bit | Hardware label | Dataset aliases | AI-model aliases |
|---|---|---|---|
| `1` | `TYPE1` | `access`, `use` | `inference`, `execute` |
| `2` | `TYPE2` | `train`, `training` | `finetune`, `fine_tune` |
| `4` | `TYPE3` | `download`, `federatedlearning`, `federated_learning` | `download` |

Aliases map to bit positions globally; the compiler does not validate whether an alias is semantically appropriate for the selected asset type. Prefer `TYPE1`–`TYPE3` in archival examples where cross-domain meaning might be unclear.

Asset types accept `hardware` (including `MCU`, `MPU`, and device aliases), `dataset`, or `AIModel`. A command-line `--asset-type` overrides inference.

## Deterministic values

The policy hash is calculated as:

```text
Keccak-256(UTF-8(JSON(policy, sorted keys, no insignificant whitespace)))
```

The asset identifier is:

```text
Keccak-256(UTF-8(first policy target))
```

JSON array order is preserved during canonicalization. Object-key order and formatting whitespace do not affect the hash. Any semantic or textual value change does.

## Command reference

```text
odrl_compiler.py INPUT [-o OUTPUT]
    [--kind auto|entitlement|asset]
    [--asset-type hardware|dataset|AIModel]
    [--policy-uri URI]
    [--valid-from UNIX_SECONDS]
    [--valid-until UNIX_SECONDS]
```

If `--output` is omitted, the compiler writes beside the input with the suffix `.onchain.json`. Use an explicit temporary output when verifying committed examples so the reference files are not overwritten.

`--kind auto` classifies a policy from its group-constraint placement. Explicit `--kind` is preferable in scripted research workflows. Validity values use Unix seconds; `0` means immediately valid or no expiry.

## Deliberately unsupported ODRL features

The compiler does not implement arbitrary ODRL operators, duties, remedies, consequences, parties, agreement/offer semantics, nested logical constraints, temporal constraints expressed inside ODRL, or general JSON-LD expansion. Unrecognized groups, asset types, or actions cause an error; other fields are retained in the hashed source policy but do not affect the enforcement masks.

This distinction is important: the on-chain representation is an enforcement projection of the source policy, not a lossless ODRL serialization or a complete ODRL evaluator.

