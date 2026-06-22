# Third-Party Licenses

AFT's own source code is licensed under the [MIT License](LICENSE).

AFT bundles the following third-party libraries, each licensed under the
**GNU Lesser General Public License, version 2.1 (LGPL-2.1)**. They are shipped
as separate dynamic libraries (`.dylib`) inside the app bundle, so they may be
replaced/relinked by the end user, as the LGPL permits.

## libmtp

- **Project:** https://github.com/libmtp/libmtp
- **Version:** 1.1.23
- **License:** GNU LGPL-2.1 — see [`licenses/libmtp-COPYING`](licenses/libmtp-COPYING)
- **Copyright:** © Linus Walleij and the libmtp contributors.

Implements the Media Transfer Protocol (MTP) used to communicate with Android
devices.

## libusb

- **Project:** https://github.com/libusb/libusb
- **Version:** 1.0.27
- **License:** GNU LGPL-2.1 — see [`licenses/libusb-COPYING`](licenses/libusb-COPYING)
- **Copyright:** © the libusb contributors.

Provides cross-platform access to USB devices, used by libmtp.

---

These libraries are built from unmodified upstream sources by
[`scripts/build-universal-deps.sh`](scripts/build-universal-deps.sh). Their full
license texts are included in the [`licenses/`](licenses/) directory. To obtain
their source code, see the project links above.

## Note on the app icon

The app icon is derived from the Android robot, which is reproduced from work
created and shared by Google and used according to terms described in the
Creative Commons 3.0 Attribution License. "Android" is a trademark of Google LLC.
AFT is not affiliated with or endorsed by Google.
