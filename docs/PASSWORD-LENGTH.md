# Login password length

With Quick Toggles installed, open Settings → Quick Tools → Login password length.

- **Remove length requirement** saves recognized minimum-length rules on this Mac, then removes those rules after administrator authorization.
- **Restore original requirement** restores the saved rules, including their original values and scope. It can finish an interrupted operation. Unrelated policy changes are preserved; conflicting length rules stop restoration.
- **Set minimum length** is available when no editable rule or recovery record exists. Choose 1–64 characters. This creates a rule for the current local account; it does not invent an earlier system default.

The app does not read or change your password. These actions change password policy. macOS controls when a restored requirement is enforced. A shorter password is easier to guess.

System-wide rules affect every local account. The section identifies that scope before confirmation. Other users' account-specific rules are not changed.

## Supported policies

This tool handles literal minimum-length predicates in the local Open Directory node and the current local account. It preserves authentication, expiration and other policy categories. Arbitrary password-content predicates, MDM enrollment and password configuration profiles are not edited. A failure to read management or policy state also blocks changes.

It never runs `pwpolicy -clearaccountpolicies` or replaces the complete policy dictionary. Every elevated request checks the account identity and the policy snapshot again. Another process changing policies can cause an operation to stop; use Refresh before retrying.

## Recovery

The original policy snapshot is stored privately as `password-length-recovery.json` in the app's Application Support container. It is bound to the local account and Mac hardware identity. It is not a preference and is not included in settings exports. It contains policy data, not passwords. Developer and official app variants have separate containers.

Authorization cancellation and partial failures retain recovery data. Restore original requirement safely adds missing original rules; rules already restored are left in place. The file is removed only after a successful restore. Unrecognized or conflicting rules block automatic recovery rather than overwriting newer policy decisions.

System policy changes persist after quitting, disabling Quick Toggles or removing the app. Restore requirements before deleting the app's data if you want the saved original values back. Reinstalling the same app variant can use retained recovery data.

## Contributor validation

`./build.sh --test-suite=password-length` exercises recognition, targeted removal, restoration, partial recovery, conflicting edits, account identity and input bounds without touching real policies.

Also run the full tests, build and selftest described in CONTRIBUTING.md. On a test Mac, verify administrator cancellation and the enable/remove/restore flow. Check the System Settings password-change flow separately: successful policy evaluation is not evidence that the UI accepted a password change. Keep the original password, and restore the initial policies after testing.
