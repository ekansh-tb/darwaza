# Installing Darwaza without an app store

None of this needs a paid developer account, except where noted.

## Android

1. Build the APK: `flutter build apk --release`. The file is
   `build/app/outputs/flutter-apk/app-release.apk`.
2. Copy it to the phone and open it. Android asks once to allow installs from that source.

The release build is signed with the default debug key. That is fine for your own
devices. Do not distribute it widely: set up a proper signing key first.

## macOS

Use the CI workflow if you do not have Xcode:

1. In the GitHub repository open the Actions tab, pick Build, then Run workflow.
2. When it finishes, download the `darwaza-macos` artifact and unzip it.
3. The app is signed ad hoc, not notarised, so macOS will refuse the first launch.
   Either right-click the app and choose Open, or run:
   `xattr -dr com.apple.quarantine darwaza.app`
4. Move it to Applications.

If you have Xcode, `flutter build macos --release` builds it locally and needs none of this.

## iPhone with a free Apple ID

Apple lets a free Apple ID put your own app on your own iPhone, with limits:

- the app stops opening after **7 days** and has to be installed again
- at most 3 apps on a device this way, and a few new app ids per week
- Developer Mode must be on (Settings, Privacy and Security) and the developer profile
  must be trusted (Settings, General, VPN and Device Management)

Without Xcode:

1. Run the CI workflow with the iPhone option ticked and download `darwaza-iphone-unsigned`.
2. Sign and install the IPA with Sideloadly or AltStore using your Apple ID. Both need
   your Apple ID login: use a separate Apple ID made for this, not your main one.
3. AltStore can refresh the app in the background every week, which hides the 7 day limit.

With Xcode, open `ios/Runner.xcworkspace`, pick your free team under Signing, and run it.

On first launch iOS asks to let the app find devices on your local network. Say yes: the
scan cannot work without it.

A paid Apple Developer account ($99 a year) removes the 7 day limit and allows TestFlight.
