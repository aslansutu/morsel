package dev.atakanonol.morsel

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.media.ExifInterface
import com.google.android.gms.common.api.OptionalModuleApi
import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * The `morsel/vision` channel (lib/vision.dart) on Google ML Kit: document scanner,
 * text recognition and subject cut-out. Everything runs on the device.
 */
class LabelVision(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val background = Executors.newSingleThreadExecutor()
    private val textRecognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
    private val segmenter by lazy {
        SubjectSegmentation.getClient(SubjectSegmenterOptions.Builder().enableForegroundBitmap().build())
    }
    private var pendingScan: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "appFolder" -> result.success(activity.filesDir.path)
            "scanDocument" -> scanDocument(result)
            "readText" -> readText(call.arguments as String, result)
            "cutOut" -> cutOut(call.arguments as String, result)
            else -> result.notImplemented()
        }
    }

    // Document scanner: Google's scanner screen, from Google Play services. It
    // straightens and crops the page, and can import from the gallery too.
    private fun scanDocument(result: MethodChannel.Result) {
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setPageLimit(1)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()
        GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
            .addOnSuccessListener { intent ->
                pendingScan = result
                activity.startIntentSenderForResult(intent, SCAN_REQUEST, null, 0, 0, 0)
            }
            .addOnFailureListener { e -> result.error("unavailable", e.message, null) }
    }

    /** Called from MainActivity; true when the result was the scanner's. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SCAN_REQUEST) return false
        val result = pendingScan ?: return true
        pendingScan = null
        val page = GmsDocumentScanningResult.fromActivityResultIntent(data)?.pages?.firstOrNull()
        if (resultCode != Activity.RESULT_OK || page == null) {
            result.success(null)
            return true
        }
        inBackground(result) {
            val file = newFile()
            activity.contentResolver.openInputStream(page.imageUri)!!.use { input ->
                file.outputStream().use { input.copyTo(it) }
            }
            file.path
        }
        return true
    }

    // Text recognition, ML Kit's Latin model.
    private fun readText(path: String, result: MethodChannel.Result) = whenInstalled(textRecognizer, result) {
        background.execute {
            val image = try {
                loadUpright(path, 2400)
            } catch (e: Exception) {
                return@execute fail(result, e)
            }
            textRecognizer.process(InputImage.fromBitmap(image, 0))
                .addOnSuccessListener { text ->
                    val w = image.width.toDouble()
                    val h = image.height.toDouble()
                    result.success(text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
                        line.boundingBox?.let { box ->
                            // How far the baseline drops per unit across, in fractions of the image.
                            val corners = line.cornerPoints
                            val run = if (corners != null) (corners[1].x - corners[0].x) / w else 0.0
                            val slope = if (corners != null && run > 0) (corners[1].y - corners[0].y) / h / run else 0.0
                            mapOf(
                                "text" to line.text,
                                "left" to box.left / w,
                                "top" to box.top / h,
                                "right" to box.right / w,
                                "bottom" to box.bottom / h,
                                "slope" to slope,
                            )
                        }
                    })
                }
                .addOnFailureListener { e -> fail(result, e) }
        }
    }

    // Subject cut-out.
    private fun cutOut(path: String, result: MethodChannel.Result) {
        whenInstalled(segmenter, result) {
            background.execute {
                val image = try {
                    loadUpright(path, 1600)
                } catch (e: Exception) {
                    return@execute fail(result, e)
                }
                segmenter.process(InputImage.fromBitmap(image, 0))
                    .addOnSuccessListener(background) { segmentation ->
                        val saved = segmentation.foregroundBitmap?.let(::onWhite)?.let(::save)
                        activity.runOnUiThread { result.success(saved) }
                    }
                    .addOnFailureListener { e -> fail(result, e) }
            }
        }
    }

    /** Runs [then] once [api]'s model is on the device: Google Play services downloads it on first use. */
    private fun whenInstalled(api: OptionalModuleApi, result: MethodChannel.Result, then: () -> Unit) {
        val modules = ModuleInstall.getClient(activity)
        val listener = object : InstallStatusListener {
            override fun onInstallStatusUpdated(update: ModuleInstallStatusUpdate) {
                when (update.installState) {
                    ModuleInstallStatusUpdate.InstallState.STATE_COMPLETED -> {
                        modules.unregisterListener(this)
                        then()
                    }
                    ModuleInstallStatusUpdate.InstallState.STATE_FAILED,
                    ModuleInstallStatusUpdate.InstallState.STATE_CANCELED -> {
                        modules.unregisterListener(this)
                        result.error("unavailable", "Couldn't download the model.", null)
                    }
                }
            }
        }
        modules.installModules(ModuleInstallRequest.newBuilder().addApi(api).setListener(listener).build())
            .addOnSuccessListener { response ->
                if (response.areModulesAlreadyInstalled()) {
                    modules.unregisterListener(listener)
                    then()
                }
            }
            .addOnFailureListener { e -> result.error("unavailable", e.message, null) }
    }

    /** The visible part of [foreground] centred on a white square, at most 1200 px across. */
    private fun onWhite(foreground: Bitmap): Bitmap? {
        val w = foreground.width
        val h = foreground.height
        val pixels = IntArray(w * h).also { foreground.getPixels(it, 0, w, 0, 0, w, h) }
        var left = w
        var top = h
        var right = -1
        var bottom = -1
        for (y in 0 until h) {
            for (x in 0 until w) {
                if (Color.alpha(pixels[y * w + x]) > 16) {
                    if (x < left) left = x
                    if (x > right) right = x
                    if (y < top) top = y
                    if (y > bottom) bottom = y
                }
            }
        }
        if (right < 0) return null
        val box = Rect(left, top, right + 1, bottom + 1)
        val side = maxOf(box.width(), box.height()) * 1.12f
        val scale = minOf(1f, 1200f / side)
        val canvasSide = (side * scale).toInt()
        val out = Bitmap.createBitmap(canvasSide, canvasSide, Bitmap.Config.ARGB_8888)
        val dw = box.width() * scale
        val dh = box.height() * scale
        Canvas(out).apply {
            drawColor(Color.WHITE)
            drawBitmap(
                foreground, box,
                RectF((canvasSide - dw) / 2, (canvasSide - dh) / 2, (canvasSide + dw) / 2, (canvasSide + dh) / 2),
                Paint(Paint.FILTER_BITMAP_FLAG),
            )
        }
        return out
    }

    /** Decodes [path] to at most about [maxSide] px across, turned the way the camera held it. */
    private fun loadUpright(path: String, maxSide: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val bitmap = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw IllegalArgumentException("Can't open the image.")
        val degrees = when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 0)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees) }, true)
    }

    private fun save(bitmap: Bitmap): String {
        val file = newFile()
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        return file.path
    }

    private fun newFile() = File(activity.cacheDir, "vision-${System.nanoTime()}.jpg")

    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        background.execute {
            try {
                val value = work()
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                fail(result, e)
            }
        }
    }

    private fun fail(result: MethodChannel.Result, e: Exception) {
        activity.runOnUiThread { result.error("vision_failed", e.message, null) }
    }

    companion object {
        private const val SCAN_REQUEST = 7301
    }
}
