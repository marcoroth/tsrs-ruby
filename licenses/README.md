# Licenses

This gem's own code is MIT licensed. It links [tsrs](https://github.com/oxc-project/tsrs) statically, which is
Apache-2.0 licensed and a derivative of [TypeScript](https://github.com/microsoft/TypeScript) (Copyright Microsoft
Corporation, also Apache-2.0). The `lib.*.d.ts` files tsrs embeds, and so this gem ships inside its native
extension, are TypeScript's.

- `tsrs-Apache-2.0.txt` is tsrs's license.
- `tsrs-NOTICE.txt` is tsrs's NOTICE file, with its attribution to TypeScript, which Apache-2.0 requires to be passed on.

Run `cargo about generate` before a release to confirm nothing in the dependency closure has been missed.
