package com.fl.pip


import android.app.Activity
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.util.Rational
import androidx.annotation.RequiresApi
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
                val state = call.arguments as Boolean
                if (state) {
                    /// 切换前台
                    val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    am.moveTaskToFront(activity.taskId, ActivityManager.MOVE_TASK_WITH_HOME)
                } else {
                    /// 切换后台
                    val intent = Intent(Intent.ACTION_MAIN)
                    intent.addCategory(Intent.CATEGORY_HOME)
                    activity.startActivity(intent)
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun dp2px(value: Int): Int {
        val scale: Float = context.resources.displayMetrics.density
        return (value * scale + 0.5f).toInt()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
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