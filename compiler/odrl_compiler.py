#!/usr/bin/env python3
"""
ODRL-to-on-chain compiler for the four-contract authorization prototype.

Supported inputs
----------------
1. Platform/user entitlement policies, e.g. User_Group1.json
2. Asset-owner policies, e.g. H9_Policy.json

The compiler does not deploy anything. It produces deterministic JSON values that
can be copied into Remix for PlatformEntitlementRegistry and AssetPolicyRegistry.

Action bits
-----------
TYPE1 -> 1
TYPE2 -> 2
TYPE3 -> 4

User groups
-----------
Group1 -> 1
Group2 -> 2
Group3 -> 3
Group4 -> 4

Asset types
-----------
Hardware -> 1
Dataset  -> 2
AIModel  -> 3
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Iterable

try:
    from Crypto.Hash import keccak
except ImportError as exc:
    raise SystemExit(
        "Missing dependency: pycryptodome\n"
        "Install it with:\n"
        "  python3 -m pip install pycryptodome"
    ) from exc


GROUP_MAP = {
    "group1": 1,
    "group2": 2,
    "group3": 3,
    "group4": 4,
}

ASSET_TYPE_MAP = {
    "hardware": 1,
    "edgehardware": 1,
    "edge_hardware": 1,
    "device": 1,
    "mcu": 1,
    "mpu": 1,
    "dataset": 2,
    "data": 2,
    "aimodel": 3,
    "ai_model": 3,
    "model": 3,
}

ACTION_MAP = {
    "type1": 1,
    "type2": 2,
    "type3": 4,

    # Optional aliases for the same three compact action slots.
    "access": 1,
    "use": 1,
    "execute": 1,
    "inference": 1,

    "train": 2,
    "training": 2,
    "finetune": 2,
    "fine_tune": 2,

    "download": 4,
    "federatedlearning": 4,
    "federated_learning": 4,
}


class PolicyCompileError(ValueError):
    pass


def ethereum_keccak256(data: bytes) -> str:
    h = keccak.new(digest_bits=256)
    h.update(data)
    return "0x" + h.hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    """Stable UTF-8 JSON representation used for the policy hash."""
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def normalize_token(value: Any) -> str:
    if value is None:
        return ""
    token = str(value).strip()
    if ":" in token:
        token = token.rsplit(":", 1)[-1]
    return (
        token.replace("-", "")
        .replace(" ", "")
        .replace("/", "")
        .lower()
    )


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def parse_group(value: Any) -> int:
    key = normalize_token(value)
    if key not in GROUP_MAP:
        raise PolicyCompileError(
            f"Unsupported user group {value!r}. Expected Group1..Group4."
        )
    return GROUP_MAP[key]


def parse_asset_type(value: Any) -> int:
    key = normalize_token(value)
    if key not in ASSET_TYPE_MAP:
        raise PolicyCompileError(
            f"Unsupported asset type {value!r}. "
            "Expected hardware, dataset, or AIModel."
        )
    return ASSET_TYPE_MAP[key]


def action_value(action: Any) -> Any:
    if isinstance(action, str):
        return action
    if not isinstance(action, dict):
        return action

    refinement = action.get("refinement")
    if isinstance(refinement, dict):
        for key in ("value", "rightOperand"):
            if key in refinement:
                return refinement[key]

    # Support a list of refinements.
    if isinstance(refinement, list):
        for item in refinement:
            if isinstance(item, dict):
                for key in ("value", "rightOperand"):
                    if key in item:
                        return item[key]

    # Fall back to the action type itself.
    return action.get("type") or action.get("@id")


def parse_action(action: Any) -> int:
    raw = action_value(action)
    key = normalize_token(raw)
    if key not in ACTION_MAP:
        raise PolicyCompileError(
            f"Unsupported action/service type {raw!r}. "
            "Expected TYPE1, TYPE2, TYPE3 or a configured alias."
        )
    return ACTION_MAP[key]


def action_mask(actions: Iterable[Any]) -> int:
    mask = 0
    for action in actions:
        mask |= parse_action(action)
    return mask


def rule_constraints(rule: dict[str, Any], policy: dict[str, Any]) -> list[dict[str, Any]]:
    local = as_list(rule.get("constraint"))
    if local:
        return [x for x in local if isinstance(x, dict)]
    return [x for x in as_list(policy.get("constraint")) if isinstance(x, dict)]


def groups_from_constraints(constraints: list[dict[str, Any]]) -> list[int]:
    values: list[Any] = []
    for constraint in constraints:
        operand = normalize_token(constraint.get("leftOperand"))
        if operand in {"allowedusergroups", "usergroup", "group"}:
            values.extend(as_list(constraint.get("rightOperand")))

    if not values:
        raise PolicyCompileError(
            "A permission/prohibition rule has no supported user-group constraint."
        )

    groups = sorted({parse_group(v) for v in values})
    return groups


def infer_policy_kind(policy: dict[str, Any]) -> str:
    # User entitlement policies generally have a top-level userGroup constraint.
    top_constraints = [
        x for x in as_list(policy.get("constraint")) if isinstance(x, dict)
    ]
    if any(
        normalize_token(c.get("leftOperand")) in {"usergroup", "group"}
        for c in top_constraints
    ):
        return "entitlement"

    # Asset policies usually have group constraints inside each rule.
    for section in ("permission", "prohibition"):
        for rule in as_list(policy.get(section)):
            if not isinstance(rule, dict):
                continue
            if any(
                normalize_token(c.get("leftOperand"))
                in {"allowedusergroups", "usergroup", "group"}
                for c in rule_constraints(rule, policy)
            ):
                return "asset"

    raise PolicyCompileError(
        "Could not infer policy kind. Use --kind entitlement or --kind asset."
    )


def infer_asset_type(policy: dict[str, Any], override: str | None) -> int:
    if override:
        return parse_asset_type(override)

    for key in ("assetType", "caie:assetType", "vlab:assetType"):
        if key in policy:
            return parse_asset_type(policy[key])

    metadata = policy.get("vlab:metadata")
    if isinstance(metadata, dict):
        target_type = metadata.get("target_type")
        if target_type:
            # Existing VLab policies use MCU/MPU for hardware.
            return parse_asset_type(target_type)

    # Existing user policies target the benchmarking service, which is hardware.
    for rule in as_list(policy.get("permission")):
        if isinstance(rule, dict):
            target = normalize_token(rule.get("target"))
            if "benchmarking" in target:
                return 1

    raise PolicyCompileError(
        "Could not infer asset type. Supply --asset-type hardware|dataset|AIModel."
    )


def first_target(policy: dict[str, Any]) -> str:
    for section in ("permission", "prohibition"):
        for rule in as_list(policy.get(section)):
            if isinstance(rule, dict) and rule.get("target"):
                return str(rule["target"]).strip()
    uid = policy.get("uid")
    if uid:
        return str(uid).strip()
    raise PolicyCompileError("Policy has no target or uid from which to derive assetId.")


def compile_entitlement(
    policy: dict[str, Any],
    asset_type_override: str | None,
) -> dict[str, Any]:
    constraints = [
        x for x in as_list(policy.get("constraint")) if isinstance(x, dict)
    ]
    groups = groups_from_constraints(constraints)
    if len(groups) != 1:
        raise PolicyCompileError(
            "A platform entitlement policy must resolve to exactly one user group."
        )

    mask = 0
    for rule in as_list(policy.get("permission")):
        if not isinstance(rule, dict):
            continue
        mask |= action_mask(as_list(rule.get("action")))

    if mask == 0:
        raise PolicyCompileError("Entitlement policy produced an empty action mask.")

    asset_type = infer_asset_type(policy, asset_type_override)
    policy_hash = ethereum_keccak256(canonical_json_bytes(policy))

    return {
        "policyKind": "platformEntitlement",
        "sourcePolicyUid": policy.get("uid"),
        "policyHash": policy_hash,
        "mapping": {
            "userGroup": groups[0],
            "assetType": asset_type,
            "actionMask": mask,
        },
        "remixArguments": {
            "group": groups[0],
            "assetType": asset_type,
            "actionMask": mask,
        },
        "decoded": {
            "group": f"Group{groups[0]}",
            "allowedActionBits": [
                bit for bit in (1, 2, 4) if mask & bit
            ],
        },
    }


def compile_asset_policy(
    policy: dict[str, Any],
    asset_type_override: str | None,
    policy_uri: str,
    valid_from: int,
    valid_until: int,
) -> dict[str, Any]:
    permission_masks = [0, 0, 0, 0]
    prohibition_masks = [0, 0, 0, 0]

    target: str | None = None

    for section, output_masks in (
        ("permission", permission_masks),
        ("prohibition", prohibition_masks),
    ):
        for rule in as_list(policy.get(section)):
            if not isinstance(rule, dict):
                continue

            if target is None and rule.get("target"):
                target = str(rule["target"]).strip()

            groups = groups_from_constraints(rule_constraints(rule, policy))
            mask = action_mask(as_list(rule.get("action")))

            for group in groups:
                output_masks[group - 1] |= mask

    if not any(permission_masks):
        raise PolicyCompileError("Asset policy produced no permission bits.")

    target = target or first_target(policy)
    asset_type = infer_asset_type(policy, asset_type_override)
    policy_hash = ethereum_keccak256(canonical_json_bytes(policy))

    # Deterministic bytes32 identifier. This avoids truncating long URNs.
    asset_id = ethereum_keccak256(target.encode("utf-8"))

    effective_masks = [
        permission_masks[i] & ~prohibition_masks[i]
        for i in range(4)
    ]

    return {
        "policyKind": "assetPolicy",
        "sourcePolicyUid": policy.get("uid"),
        "target": target,
        "assetId": asset_id,
        "assetType": asset_type,
        "policyHash": policy_hash,
        "policyURI": policy_uri,
        "permissionMasks": permission_masks,
        "prohibitionMasks": prohibition_masks,
        "effectiveMasks": effective_masks,
        "validFrom": valid_from,
        "validUntil": valid_until,
        "remixArguments": {
            "assetId": asset_id,
            "policyHash": policy_hash,
            "policyURI": policy_uri,
            "permissionMasks": permission_masks,
            "prohibitionMasks": prohibition_masks,
            "validFrom": valid_from,
            "validUntil": valid_until,
        },
        "decoded": {
            f"Group{i + 1}": {
                "permissionMask": permission_masks[i],
                "prohibitionMask": prohibition_masks[i],
                "effectiveMask": effective_masks[i],
                "effectiveActionBits": [
                    bit for bit in (1, 2, 4) if effective_masks[i] & bit
                ],
            }
            for i in range(4)
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compile ODRL JSON into compact smart-contract arguments."
    )
    parser.add_argument("input", type=Path, help="Input ODRL JSON file")
    parser.add_argument(
        "-o", "--output", type=Path,
        help="Output JSON file. Defaults to <input>.onchain.json"
    )
    parser.add_argument(
        "--kind",
        choices=("auto", "entitlement", "asset"),
        default="auto",
        help="Policy kind; default: auto"
    )
    parser.add_argument(
        "--asset-type",
        choices=("hardware", "dataset", "AIModel"),
        help="Override asset type inference"
    )
    parser.add_argument(
        "--policy-uri",
        default="",
        help="Off-chain policy URI, e.g. ipfs://... or https://..."
    )
    parser.add_argument(
        "--valid-from",
        type=int,
        default=0,
        help="Unix timestamp; 0 means immediately valid"
    )
    parser.add_argument(
        "--valid-until",
        type=int,
        default=0,
        help="Unix timestamp; 0 means no expiry"
    )

    args = parser.parse_args()

    try:
        with args.input.open("r", encoding="utf-8") as handle:
            policy = json.load(handle)

        if not isinstance(policy, dict):
            raise PolicyCompileError("Top-level JSON value must be an object.")

        kind = args.kind
        if kind == "auto":
            kind = infer_policy_kind(policy)

        if kind == "entitlement":
            result = compile_entitlement(policy, args.asset_type)
        else:
            result = compile_asset_policy(
                policy,
                args.asset_type,
                args.policy_uri,
                args.valid_from,
                args.valid_until,
            )

        output = args.output or args.input.with_suffix(".onchain.json")
        with output.open("w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2, ensure_ascii=False)
            handle.write("\n")

        print(json.dumps(result, indent=2, ensure_ascii=False))
        print(f"\nWritten to: {output}")
        return 0

    except (OSError, json.JSONDecodeError, PolicyCompileError) as exc:
        print(f"Compilation failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
