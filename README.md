# fl_pip

## 基于原生ios和android的画中画模式，实现显示flutter的view,可以通过修改flutter 栈顶的view来显示任意UI

## The picture-in-picture mode is implemented in native ios and android to display flutter's view

## Use configuration

- ios 配置 : `Signing & Capabilities` -> `Capability` 添加 `BackgroundModes` 勾选 `Audio,AirPlay,And Picture in Picture`
- ios configuration : `Signing & Capabilities` -> `Capability` Add `BackgroundModes` check `Audio,AirPlay,And Picture in Picture`

- android 配置 : `android/app/src/main/${your package name}/MainActivity` 修改 MainActivity 继承,
- android configuration : `android/app/src/main/${your package name}/MainActivity`,

### kotlin

```kotlin

class MainActivity : FlPiPActivity()

```

### java

```java

class MainActivity extends FlPiPActivity {

}

```

android AndroidManifest file `android/app/src/main/AndroidManifest.xml`, add ` android:supportsPictureInPicture="true"`

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

/// 退出画中画
/// Quit painting in picture
void disable() {
  FlPiP().disable();
}
```

- 如果使用enableWithEngine方法必须在main文件中添加这个main方法
- The main method must be added to the main file if the enableWithEngine method is used

```dart
/// mainName must be the same as the method name
@pragma('vm:entry-point')
void pipMain() {
  runApp(YourApp());
}

```

## Display effect

| android                                                                                        | ios                                                                                       |
|------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| <img src="https://github.com/Wayaer/fl_pip/raw/main/example/assets/android.gif" width="100%"/> | <img src="https://github.com/Wayaer/fl_pip/raw/main/example/assets/ios.gif" width="75%"/> |
