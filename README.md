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

```HTML

<video src="https://github.com/Wayaer/fl_pip/blob/a4313a9f24bf79142a082884038676e09ceb961e/example/assets/android.mp4" controls="controls" width="500" height="300"></video>
<video src="https://github.com/Wayaer/fl_pip/blob/a4313a9f24bf79142a082884038676e09ceb961e/example/assets/ios.mp4" controls="controls" width="500" height="300"></video>
```