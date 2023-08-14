package com.fl.pip


import android.app.Activity
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.util.Log
import android.util.Rational
import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** FlPiPPlugin */
class FlPiPPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    companion object {
        lateinit var channel: MethodChannel
    }

    private lateinit var context: Context
    private lateinit var activity: Activity

    private var engineId = "pip.flutter"
    private var engine: FlutterEngine? = null
    private var flutterView: FlutterView? = null
    private var container: FrameLayout? = null
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "fl_pip")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    @RequiresApi(Build.VERSION_CODES.N)
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "enable" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success(2)
                    return
                }
                val args = call.arguments as Map<*, *>
                val builder = PictureInPictureParams.Builder().apply {
                    setAspectRatio(Rational(args["numerator"] as Int, args["denominator"] as Int))
                    setSourceRectHint(Rect(0, 0, 0, 0))
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setSeamlessResizeEnabled(false)
                    }
                }
                result.success(if (activity.enterPictureInPictureMode(builder.build())) 0 else 1)
            }

            "enableWithEngine" -> result.success(enableWithEngine())
            "disable" -> {
                foreground()
                destroyEngin()
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

            "available" -> result.success(activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE))
            "toggle" -> {
                if (call.arguments as Boolean) {
                    foreground()
                } else {
                    background()
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun enableWithEngine(): Boolean {
        if (engine == null) {
            container = FrameLayout(context)
            flutterView = FlutterView(context)
            val engineGroup = FlutterEngineGroup(context)
            val dartEntrypoint = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(), "pipMain"
            )
            engine = engineGroup.createAndRunEngine(context, dartEntrypoint)
            FlutterEngineCache.getInstance().put(engineId, engine)

            engine!!.platformViewsController.attach(
                context, engine!!.renderer, engine!!.dartExecutor
            )
            flutterView!!.attachToFlutterEngine(engine!!)
            val displayMetrics = context.resources.displayMetrics
            val height = displayMetrics.heightPixels
            container!!.addView(
                flutterView!!, FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, (height * 0.3).toInt()
                )
            )
            engine!!.lifecycleChannel.appIsResumed()
        }
        return true
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

    private fun destroyEngin() {
        container = null
        flutterView?.detachFromFlutterEngine()
        flutterView = null
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
        destroyEngin()
    }

    override fun onDetachedFromActivity() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {}


}