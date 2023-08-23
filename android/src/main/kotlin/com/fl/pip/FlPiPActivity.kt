package com.fl.pip

import android.app.Activity
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.annotation.RequiresApi
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


open class FlPiPActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        flutterEngine?.plugins?.add(PiPPlugin())
    }


    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        PiPPlugin.setPiPStatus(if (isInPictureInPictureMode) 0 else 1)
    }

    private class PiPPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

        companion object {
            lateinit var channel: MethodChannel

            fun setPiPStatus(int: Int) {
                channel.invokeMethod("onPiPStatus", int)
            }
        }

        private lateinit var context: Context
        private lateinit var activity: Activity
        private lateinit var pluginBinding: FlutterPlugin.FlutterPluginBinding

        private var engineId = "pip.flutter"
        private var engine: FlutterEngine? = null
        private var flutterView: FlutterView? = null
        private var rootView: FrameLayout? = null
        private lateinit var windowManager: WindowManager

        override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            pluginBinding = binding
            context = binding.applicationContext
            channel = MethodChannel(binding.binaryMessenger, "fl_pip")
            channel.setMethodCallHandler(this)
            windowManager = context.getSystemService(Service.WINDOW_SERVICE) as WindowManager
        }

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "enable" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.success(2)
                        return
                    }
                    val args = call.arguments as Map<*, *>
                    val builder = PictureInPictureParams.Builder().apply {
                        setAspectRatio(
                            Rational(
                                args["numerator"] as Int, args["denominator"] as Int
                            )
                        )
                        setSourceRectHint(Rect(0, 0, 0, 0))
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            setSeamlessResizeEnabled(false)
                        }
                    }
                    result.success(if (activity.enterPictureInPictureMode(builder.build())) 0 else 1)
                }

                "enableWithEngine" -> result.success(enableWithEngine(call.arguments as Map<*, *>))
                "disable" -> {
                    disable()
                    result.success(null)
                }

                "isActive" -> {
                    val isAvailable =
                        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE);
                    if (isAvailable) {
                        result.success(if (activity.isInPictureInPictureMode) 0 else 1)
                    } else {
                        result.success(2)
                    }
                }

                "available" -> result.success(
                    activity.packageManager.hasSystemFeature(
                        PackageManager.FEATURE_PICTURE_IN_PICTURE
                    )
                )

                "toggle" -> {
                    if (call.arguments as Boolean) {
                        foreground()
                    } else {
                        background()
                    }
                    result.success(null)
                }

                "launchApp" -> {
                    val intent = Intent(context, activity.javaClass)
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    activity.startActivity(intent)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        private fun disable() {
            setPiPStatus(1)
            foreground()
            disposeEngine()
        }

        @RequiresApi(Build.VERSION_CODES.M)
        private fun enableWithEngine(map: Map<*, *>): Int {
            if (!checkPermission()) {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                    data = Uri.parse("package:${context.packageName}")
                })
                setPiPStatus(1)
                return 1
            }
            val displayMetrics = context.resources.displayMetrics
            if (engine == null) {
                flutterView = FlutterView(context, FlutterSurfaceView(context, true))
                flutterView!!.elevation = 0F
                val dartEntrypoint = DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(), "pipMain"
                )
                val engineGroup = pluginBinding.engineGroup ?: FlutterEngineGroup(context)
                engine = engineGroup.createAndRunEngine(context, dartEntrypoint)
                GeneratedPluginRegister.registerGeneratedPlugins(engine!!)
                FlutterEngineCache.getInstance().put(engineId, engine)
                flutterView!!.attachToFlutterEngine(engine!!)

                engine!!.platformViewsController.attach(
                    context, engine!!.renderer, engine!!.dartExecutor
                )
                engine!!.lifecycleChannel.appIsResumed()
            }
            val w = (map["width"] as Double?)?.toInt() ?: (displayMetrics.widthPixels - 100)
            val h = (map["height"] as Double?)?.toInt() ?: 600
            val layoutParams = WindowManager.LayoutParams().apply {
                type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("Deprecation") WindowManager.LayoutParams.TYPE_TOAST
                }
                format = PixelFormat.TRANSLUCENT
                flags =
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                width = w
                height = h
                gravity = Gravity.START or Gravity.TOP
                x = (map["left"] as Double?)?.toInt() ?: 50
                y = (map["top"] as Double?)?.toInt() ?: (displayMetrics.heightPixels / 2)
            }
            rootView = FrameLayout(context)
            rootView!!.addView(flutterView, FrameLayout.LayoutParams(w, h))
            val close = ImageView(context)
            close.setOnClickListener {
                this.disable()
            }
            val packageName = map["packageName"] as String?
            val closeIConPath: String = if (packageName == null) {
                pluginBinding.flutterAssets.getAssetFilePathByName(map["path"] as String)
            } else {
                pluginBinding.flutterAssets.getAssetFilePathByName(
                    map["path"] as String, packageName
                )
            }
            val bitmap = BitmapFactory.decodeStream(context.assets.open(closeIConPath))
            close.setImageBitmap(bitmap)
            val closeLayoutParams = FrameLayout.LayoutParams(
                dp2px(22), dp2px(22)
            )
            closeLayoutParams.gravity = Gravity.END
            closeLayoutParams.setMargins(0, dp2px(4), dp2px(4), 0)
            rootView!!.addView(close, closeLayoutParams)
            @Suppress("ClickableViewAccessibility") flutterView!!.setOnTouchListener(object :
                View.OnTouchListener {
                private var initialX: Int = 0
                private var initialY: Int = 0
                private var initialTouchX: Float = 0f
                private var initialTouchY: Float = 0f

                override fun onTouch(view: View, event: MotionEvent): Boolean {
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            initialX = layoutParams.x
                            initialY = layoutParams.y
                            initialTouchX = event.rawX
                            initialTouchY = event.rawY
                        }

                        MotionEvent.ACTION_MOVE -> {
                            val dx = event.rawX - initialTouchX
                            val dy = event.rawY - initialTouchY
                            layoutParams.x = (initialX + dx).toInt()
                            layoutParams.y = (initialY + dy).toInt()
                            windowManager.updateViewLayout(rootView, layoutParams)
                        }
                    }
                    return false
                }
            })
            windowManager.addView(rootView, layoutParams)
            setPiPStatus(0)
            return 0
        }

        private fun background() {
            /// 切换后台
            val intent = Intent(Intent.ACTION_MAIN)
            intent.addCategory(Intent.CATEGORY_HOME)
            activity.startActivity(intent)
        }

        private fun foreground() {
            /// 切换前台
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.moveTaskToFront(activity.taskId, ActivityManager.MOVE_TASK_WITH_HOME)
        }

        private fun disposeEngine() {
            if (flutterView != null) {
                flutterView?.detachFromFlutterEngine()
                windowManager.removeView(rootView)
            }
            flutterView = null
            rootView = null
            engine?.let {
                it.destroy()
                FlutterEngineCache.getInstance().remove(engineId)
            }
            engine = null
        }

        private fun dp2px(value: Int): Int {
            val scale: Float = context.resources.displayMetrics.density
            return (value * scale + 0.5f).toInt()
        }

        override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            channel.setMethodCallHandler(null)
            disposeEngine()
        }

        override fun onDetachedFromActivity() {}

        override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
            activity = binding.activity
        }

        override fun onAttachedToActivity(binding: ActivityPluginBinding) {
            activity = binding.activity
        }

        override fun onDetachedFromActivityForConfigChanges() {}

        private fun checkPermission(): Boolean {
            var result = true
            if (Build.VERSION.SDK_INT >= 23) {
                try {
                    val clazz: Class<*> = Settings::class.java
                    val canDrawOverlays =
                        clazz.getDeclaredMethod("canDrawOverlays", Context::class.java)
                    result = canDrawOverlays.invoke(null, context) as Boolean
                } catch (e: Exception) {
                    Log.e("checkPermission", Log.getStackTraceString(e))
                }
            }
            return result
        }

    }

}