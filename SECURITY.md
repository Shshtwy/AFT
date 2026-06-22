# Security Policy

## Reporting a Vulnerability

If you discover a security issue in AFT, please report it **privately** rather
than opening a public issue:

- Preferred: use GitHub's **"Report a vulnerability"** button under the
  repository's **Security** tab (this opens a private advisory), or
- Email the maintainer if you prefer.

Please give us a reasonable amount of time to investigate and release a fix
before any public disclosure. We aim to acknowledge reports within a few days.

## Supported Versions

The latest released version receives security updates.

| Version | Supported |
| ------- | --------- |
| Latest release (`v1.x`) | ✅ |
| Older releases | ❌ |

## Scope and Notes

AFT is a local macOS utility for transferring files to and from Android devices
over USB. A few things worth knowing for security review:

- **No network access.** AFT makes no outbound connections and collects no
  telemetry or analytics of any kind.
- **Not sandboxed.** Raw USB access via `libusb`/`libmtp` is incompatible with
  the macOS App Sandbox, so the app runs unsandboxed.
- **Device claiming.** To take control of the USB device, AFT briefly terminates
  macOS's `ptpcamerad`/`mscamerad-xpc` helpers (which otherwise hold the device).
  These are user-level system agents that relaunch automatically; AFT does not
  modify, disable, or persist any system state.
- **Third-party libraries.** AFT bundles `libmtp` and `libusb` (LGPL-2.1), built
  from unmodified upstream sources — see
  [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).

The full source is available in this repository; you are encouraged to build it
yourself.
