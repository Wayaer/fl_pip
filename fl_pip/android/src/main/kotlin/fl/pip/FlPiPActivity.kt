package fl.pip

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * 宿主 Activity 必须继承该基类，插件才能收到画中画、前后台和权限结果回调。
 *
 * Host activity must extend this class so the plugin receives PiP, lifecycle and permission
 * callbacks.
 */
open class FlPiPActivity : FlutterActivity() {
    private val windowManager: FlPiPWindowManager = FlPiPWindowManager.getInstance()


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        windowManager.setActivity(this, this.applicationContext)
    }

    override fun onDestroy() {
        windowManager.clearActivity(this)
        super.onDestroy()
    }


    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        windowManager.onPictureInPictureModeChanged(isInPictureInPictureMode)
    }

    override fun onPause() {
        super.onPause()
        windowManager.onActivityPaused()
    }

    override fun onResume() {
        super.onResume()
        windowManager.onActivityResume()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        windowManager.onActivityResult(requestCode)
    }

}
