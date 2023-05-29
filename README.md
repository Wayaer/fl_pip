# fl_pip

## Use configuration

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

## Methods available

```dart
/// 开启画中画
/// Open picture-in-picture
void enable() {
  FlPiP().enable(
      iosConfig: FlPiPiOSConfig(),
      androidConfig: FlPiPAndroidConfig(
          aspectRatio: const Rational.maxLandscape()));
}

/// 是否支持画中画
/// Whether to support picture in picture
void isAvailable() {
  FlPiP().isAvailable;
}

/// 画中画状态
/// Picture-in-picture window state
void isActive() {
  FlPiP().isActive;
}

/// 切换前后台
/// Toggle front and back
/// ios仅支持切换后台
/// ios supports background switching only
void toggle() {
  FlPiP().toggle();
}
```

## Display effect

| android | ios                                                                                       |
| --- |-------------------------------------------------------------------------------------------|
| <img src="https://github.com/Wayaer/fl_pip/raw/main/example/assets/android.gif" width="100%"/> | <img src="https://github.com/Wayaer/fl_pip/raw/main/example/assets/ios.gif" width="78%"/> |
