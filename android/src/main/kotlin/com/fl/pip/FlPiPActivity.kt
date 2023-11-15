package com.fl.pip

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
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
            fun setPiPStatus(int: Int) {
                channel.invokeMethod("onPiPStatus", int)
            }
        }

        private var pipHelper: FlPiPHelper? = null
        private var enabledWhenBackground = false
        private lateinit var context: Context
        private lateinit var activity: Activity
        private lateinit var pluginBinding: FlutterPlugin.FlutterPluginBinding


        override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            pluginBinding = binding
            context = binding.applicationContext
            channel = MethodChannel(binding.binaryMessenger, "fl_pip")
            channel.setMethodCallHandler(this)
        }

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "enable" -> {
                    val args = call.arguments as Map<*, *>
                    enabledWhenBackground = args["enabledWhenBackground"] as Boolean
                    var status = false
                    if (pipHelper != null && pipHelper!!.createNewEngine && pipHelper!!.engine == null) {
                        pipHelper = null
                    }
                    if (pipHelper == null) {
                        pipHelper = FlPiPHelper(
                            pluginBinding, args, activity, context
                        ) { disposeHelper() }
                        if (!enabledWhenBackground) status = pipHelper!!.enable()
                    }
                    result.success(status)
                }

                "disable" -> {
                    disposeHelper()
                    launchApp()
                    result.success(true)
                }

                "isActive" -> {
                    val isAvailable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    } else {
                        false
                    }
                    if (isAvailable) {
                        result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInPictureInPictureMode) 0 else 1)
                    } else {
                        result.success(2)
                    }
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

        private fun disposeHelper() {
            pipHelper?.dispose()
            pipHelper = null
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
            override fun onActivityResumed(activity: Activity) {
                if (pipHelper == null) return
                if (!pipHelper!!.createNewEngine) {
                    pipHelper!!.isEnable = false
                    pipHelper = null
                }
            }

            override fun onActivityPaused(activity: Activity) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && enabledWhenBackground) {
                    pipHelper?.enable()
                }
            }

            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        }

        override fun onDetachedFromActivityForConfigChanges() {
        }

    }

}