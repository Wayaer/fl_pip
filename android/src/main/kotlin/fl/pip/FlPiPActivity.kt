package fl.pip

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
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


    class PiPPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

        companion object {
            private lateinit var channel: MethodChannel
            private var createNewEngine = false
            private var enabledWhenBackground = false
            fun setPiPStatus(int: Int) {
                channel.invokeMethod(
                    "onPiPStatus", mapOf(
                        "createNewEngine" to createNewEngine,
                        "enabledWhenBackground" to enabledWhenBackground,
                        "status" to int,
                    )
                )
            }
        }


        private lateinit var context: Context
        private lateinit var activity: Activity
        private lateinit var pluginBinding: FlutterPlugin.FlutterPluginBinding

        private var enableArgs: Map<*, *> = mutableMapOf<String, Any?>()

        private var engineId = "pip.flutter"
        private var engine: FlutterEngine? = null
        private var flutterView: FlutterView? = null
        private var windowManager: WindowManager? = null
        private var rootView: FrameLayout? = null
        private var isEnabled = false


        override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            pluginBinding = binding
            context = binding.applicationContext
            channel = MethodChannel(binding.binaryMessenger, "fl_pip")
            channel.setMethodCallHandler(this)
        }

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "enable" -> {
                    enableArgs = call.arguments as Map<*, *>
                    enabledWhenBackground = enableArgs["enabledWhenBackground"] as Boolean
                    if (!enabledWhenBackground) {
                        result.success(enable())
                        return
                    }
                    result.success(false)
                }

                "disable" -> {
                    createNewEngine = false
                    enabledWhenBackground = false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInPictureInPictureMode) {
                        launchApp()
                    }
                    disposeEngine()
                    setPiPStatus(1)
                    result.success(true)
                }

                "isActive" -> {
                    val map = mutableMapOf<String, Any>(
                        "createNewEngine" to createNewEngine,
                        "enabledWhenBackground" to enabledWhenBackground
                    )
                    val isAvailable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    } else {
                        false
                    }
                    if (isAvailable) {
                        map["status"] =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInPictureInPictureMode) 0 else 1
                    } else {
                        map["status"] = 2
                    }
                    result.success(map)
                }

                "available" -> result.success(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    } else false
                )

                "toggle" -> {
                    if (call.arguments as Boolean) {
                        launchApp()
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


        private fun background() {
            /// 切换后台
            val intent = Intent(Intent.ACTION_MAIN)
            intent.addCategory(Intent.CATEGORY_HOME)
            activity.startActivity(intent)
        }


        private fun launchApp() {
            /// 启动app
            val intent =
                activity.packageManager.getLaunchIntentForPackage(activity.applicationContext.packageName)
            intent?.flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            activity.startActivity(intent)
            isEnabled = false
        }


        private fun enable(): Boolean {
            if (isEnabled) return false
            createNewEngine = enableArgs["createNewEngine"] as Boolean
            val isEnabled = if (createNewEngine) {
                enableWM(activity)
            } else {
                enablePiP(activity)
            }
            return isEnabled
        }


        private fun enablePiP(activity: Activity): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                return false
            }
            val pipBuilder = PictureInPictureParams.Builder().apply {
                setAspectRatio(
                    Rational(
                        enableArgs["numerator"] as Int, enableArgs["denominator"] as Int
                    )
                )
                setSourceRectHint(Rect(0, 0, 0, 0))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setSeamlessResizeEnabled(false)
                }
            }
            return activity.enterPictureInPictureMode(pipBuilder.build())
        }

        private fun enableWM(activity: Activity): Boolean {
            if (!checkPermission()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                        data = Uri.parse("package:${context.packageName}")
                    })
                }
                setPiPStatus(1)
                return false
            }

            val displayMetrics = context.resources.displayMetrics
            if (engine == null) {
                flutterView = FlutterView(context, FlutterSurfaceView(context, true))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    flutterView!!.elevation = 0F
                }
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
            val w = (enableArgs["width"] as Double?)?.toInt() ?: (displayMetrics.widthPixels - 100)
            val h = (enableArgs["height"] as Double?)?.toInt() ?: 600
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
                x = (enableArgs["left"] as Double?)?.toInt() ?: 50
                y = (enableArgs["top"] as Double?)?.toInt() ?: (displayMetrics.heightPixels / 2)
            }
            rootView = FrameLayout(context)
            rootView!!.addView(flutterView, FrameLayout.LayoutParams(w, h))
            val close = ImageView(context)
            close.setOnClickListener {
                setPiPStatus(1)
                /// 切换前台
                val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                am.moveTaskToFront(activity.taskId, ActivityManager.MOVE_TASK_WITH_HOME)
                disposeEngine()
            }
            val packageName = enableArgs["packageName"] as String?
            val closeIConPath: String = if (packageName == null) {
                pluginBinding.flutterAssets.getAssetFilePathByName(enableArgs["path"] as String)
            } else {
                pluginBinding.flutterAssets.getAssetFilePathByName(
                    enableArgs["path"] as String, packageName
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
            windowManager = context.getSystemService(Service.WINDOW_SERVICE) as WindowManager
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
                            windowManager!!.updateViewLayout(rootView, layoutParams)
                        }
                    }
                    return false
                }
            })
            windowManager!!.addView(rootView, layoutParams)
            setPiPStatus(0)
            return true
        }


        private fun checkPermission(): Boolean {
            var result = true
            if (Build.VERSION.SDK_INT >= 23) {
                try {
                    val clazz: Class<*> = Settings::class.java
                    val canDrawOverlays =
                        clazz.getDeclaredMethod("canDrawOverlays", Context::class.java)
                    result = canDrawOverlays.invoke(null, context) as Boolean
                } catch (e: Exception) {
                    println("FlPiP checkPermission error : ${Log.getStackTraceString(e)}")
                }
            }
            return result
        }

        private fun disposeEngine() {
            if (flutterView != null) {
                flutterView?.detachFromFlutterEngine()
                windowManager?.removeView(rootView)
            }
            flutterView = null
            rootView = null
            engine?.let {
                it.destroy()
                FlutterEngineCache.getInstance().remove(engineId)
            }
            engine = null
            isEnabled = false
        }

        private fun dp2px(value: Int): Int {
            val scale: Float = context.resources.displayMetrics.density
            return (value * scale + 0.5f).toInt()
        }

        override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            channel.setMethodCallHandler(null)
        }

        override fun onDetachedFromActivity() {
            activity.application.unregisterActivityLifecycleCallbacks(activityLifecycleCallbacks)
        }

        override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
            onAttachedToActivity(binding)
        }

        override fun onAttachedToActivity(binding: ActivityPluginBinding) {
            activity = binding.activity
            activity.application.registerActivityLifecycleCallbacks(activityLifecycleCallbacks)
        }

        private var activityLifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && enabledWhenBackground) {
                    enable()
                }
            }

            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        }

        override fun onDetachedFromActivityForConfigChanges() {}

    }

}