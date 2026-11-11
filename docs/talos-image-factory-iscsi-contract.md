# Talos image-factory iSCSI contract

## Intent

Production Talos images require `siderolabs/iscsi-tools`. The reviewed source
contract is `terraform/contracts/talos-image-factory.json`; it makes this
extension and the factory metal-installer URL form reviewable without exposing
or replacing the protected production `talos_image` value.

The contract is deliberately separate from image generation. It does **not**
apply a MachineConfig, upgrade a node, reboot a NAS, or perform I/O testing.

## Expected image derivation

For a reviewed Factory schematic ID and a reviewed Talos version, the intended
installer form is:

```text
https://factory.talos.dev/installer/<schematic_id>:<talos_version>
```

The current opaque production URL remains the rollback reference until a
separate migration proves the generated URL is byte-for-byte equivalent.

## Safe future rollout gate

A later, separately approved change may introduce Talos-provider Factory image
generation only when all of the following are recorded in its PR:

1. a saved production plan generated without apply;
2. an exact equality comparison between its generated installer URL and the
   protected current `talos_image` URL, performed without printing credentials;
3. an explicit allowlist proving the plan has **zero**
   `talos_machine_configuration_apply` actions;
4. Verity approval of the source/plan evidence; and
5. Electra authorization for any later non-disruptive runtime observation.

## Rollback

If the equivalence proof, plan allowlist, or later approved observation fails,
stop before apply. Retain the existing protected `talos_image` URL and revert
only the new source contract/generation PR as applicable. No node rollback,
NAS reboot, filesystem repair, or cluster mutation is authorized by this
contract.
