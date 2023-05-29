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

<video id="video" controls="" preload="none" poster="Android">
      <source id="mp4" src="./example/assets/android.mp4" type="video/mp4">
</video>

<video id="video" controls="" preload="none" poster="iOS">
      <source id="mp4" src="./example/assets/ios.mp4" type="video/mp4">
</video>