# Reproducibility

## Environment

- Python 3.9 or later
- `pycryptodome` version constrained by `compiler/requirements.txt`
- Solidity compiler compatible with `^0.8.24`

Create an isolated Python environment from the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r compiler/requirements.txt
```

## Regenerate reference outputs

Use a temporary directory because the compiler's output contains the command-line policy URI:

```bash
python3 compiler/odrl_compiler.py \
  compiler/examples/H9_Policy.json \
  --kind asset \
  --asset-type hardware \
  --policy-uri "ipfs://replace-with-real-cid" \
  --output /tmp/H9_Policy.onchain.json

python3 compiler/odrl_compiler.py \
  compiler/examples/User_dAIedge.json \
  --kind entitlement \
  --asset-type hardware \
  --output /tmp/User_dAIedge.onchain.json

diff -u compiler/examples/H9_Policy.onchain.json /tmp/H9_Policy.onchain.json
diff -u compiler/examples/User_dAIedge.onchain.json /tmp/User_dAIedge.onchain.json
```

No `diff` output means the generated artifacts match the committed references.

## Expected summaries

| Example | Expected result |
|---|---|
| `User_dAIedge.json` | group `1`, asset type `1`, action mask `7` |
| `H9_Policy.json` | permission masks `[3,3,3,1]`, prohibition masks `[0,0,0,2]`, effective masks `[3,3,3,1]` |

Run the automated checks:

```bash
python3 -m unittest discover -s tests -v
```

## Reporting checklist

For paper review or artifact evaluation, report:

- repository revision or release tag;
- Python, dependency, and Solidity compiler versions;
- Solidity optimizer runs and EVM target;
- chain/network ID and deployed contract addresses;
- exact source policy files and compiler options;
- transactions and emitted events used for evaluation;
- whether the policy and metadata URIs are archival and publicly retrievable.

The supplied IPFS URI is a placeholder and must be replaced before publication if the paper claims policy retrievability.

