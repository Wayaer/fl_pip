# fl_pip

- ios configuration
  `Signing & Capabilities` -> `Capability` Add `BackgroundModes` check `Audio,AirPlay,And Picture in Picture`

- android configuration
  `android/app/src/main/${your package name}/MainActivity`,

```kotlin

class MainActivity : FlPiPActivity()

```

`android/app/src/main/AndroidManifest.xml`, add ` android:supportsPictureInPicture="true"`

```xml

<application android:label="FlPiP">
    <activity android:name=".MainActivity" android:launchMode="singleTop" android:supportsPictureInPicture="true" />
</application>
```

| android | ios |
| --- |---|
| <img src="https://github.com/Wayaer/fl_pip/raw/main/example/assets/android.gif" width="100%"/> | <img src="https://github.com/Wayaer/fl_pip/raw/main/example/assets/ios.gif" width="100%"/> |
