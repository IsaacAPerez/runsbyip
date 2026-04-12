# Info.plist Configuration

Required entries for RunsByIP iOS app:

## Privacy Descriptions
- **NSCameraUsageDescription**: "RunsByIP needs camera access to upload your profile photo."

## Background Modes
- **UIBackgroundModes**: `remote-notification`

## URL Schemes
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>runsbyip</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.runsbyip.ios</string>
    </dict>
</array>
```

## App Transport Security
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>
```
