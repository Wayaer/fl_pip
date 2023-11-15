package com.fl.pip

import android.app.Activity
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.graphics.Rect
import android.net.Uri
import android.os.Build
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
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister

class FlPiPHelper(
    private val pluginBinding: FlutterPlugin.FlutterPluginBinding,
    private val args: Map<*, *>,
    private val activity: Activity,
    private val context: Context,
    private val disposeHelper: () -> Unit
) {
    private var engineId = "pip.flutter"
    var engine: FlutterEngine? = null
    private var flutterView: FlutterView? = null
    private var windowManager: WindowManager? = null
    private var rootView: FrameLayout? = null
    var isEnable = false

    var createNewEngine = false
    fun enable(): Boolean {
        if (isEnable) return false
        createNewEngine = args["createNewEngine"] as Boolean
        isEnable = if (createNewEngine) {
            enableWM(activity)
        } else {
            enablePiP(activity)
        }
        return isEnable
    }


    private fun enablePiP(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        val pipBuilder = PictureInPictureParams.Builder().apply {
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
        return activity.enterPictureInPictureMode(pipBuilder.build())
    }

    private fun enableWM(activity: Activity): Boolean {
        if (!checkPermission()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                    data = Uri.parse("package:${context.packageName}")
                })
            }
            FlPiPActivity.PiPPlugin.setPiPStatus(1)
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
        val w = (args["width"] as Double?)?.toInt() ?: (displayMetrics.widthPixels - 100)
        val h = (args["height"] as Double?)?.toInt() ?: 600
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
            x = (args["left"] as Double?)?.toInt() ?: 50
            y = (args["top"] as Double?)?.toInt() ?: (displayMetrics.heightPixels / 2)
        }
        rootView = FrameLayout(context)
        rootView!!.addView(flutterView, FrameLayout.LayoutParams(w, h))
        val close = ImageView(context)
        close.setOnClickListener {
            FlPiPActivity.PiPPlugin.setPiPStatus(1)
            /// 切换前台
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.moveTaskToFront(activity.taskId, ActivityManager.MOVE_TASK_WITH_HOME)
            dispose()
            disposeHelper()
        }
        val packageName = args["packageName"] as String?
        val closeIConPath: String = if (packageName == null) {
            pluginBinding.flutterAssets.getAssetFilePathByName(args["path"] as String)
        } else {
            pluginBinding.flutterAssets.getAssetFilePathByName(
                args["path"] as String, packageName
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
        FlPiPActivity.PiPPlugin.setPiPStatus(0)
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
                Log.e("checkPermission", Log.getStackTraceString(e))
            }
        }
        return result
    }

    fun dispose() {
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
        isEnable = false
    }

    private fun dp2px(value: Int): Int {
        val scale: Float = context.resources.displayMetrics.density
        return (value * scale + 0.5f).toInt()
    }

}