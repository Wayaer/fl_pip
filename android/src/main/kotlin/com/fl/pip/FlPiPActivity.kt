package com.fl.pip

import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity

open class FlPiPActivity : FlutterActivity() {

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        FlPiPPlugin.setPiPStatus(if (isInPictureInPictureMode) 0 else 1)
    }

}