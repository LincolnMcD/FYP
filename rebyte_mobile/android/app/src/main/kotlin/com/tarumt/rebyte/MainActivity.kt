package com.tarumt.rebyte

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity(), SensorEventListener, LocationListener {
    private val HARDWARE_CHANNEL = "com.tarumt.rebyte/hardware"
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var tts: TextToSpeech? = null
    private var isTtsInitialized = false
    private var pendingTtsText: String? = null

    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null
    private var proximitySensor: Sensor? = null
    private var lightSensor: Sensor? = null

    // Live sensor values
    private var accelX = 0f
    private var accelY = 0f
    private var accelZ = 9.8f
    private var accelEventsCount = 0

    private var gyroX = 0f
    private var gyroY = 0f
    private var gyroZ = 0f
    private var gyroEventsCount = 0

    private var proximityDistance = -1f
    private var proximityMaxRange = 5f
    private var proximityEventsCount = 0

    private var lightLux = -1f
    private var lightEventsCount = 0

    // GPS / Location
    private var locationManager: LocationManager? = null
    private var lastLocation: Location? = null
    private var locationUpdatesCount = 0

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize TTS for Test 5 spoken voice
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                tts?.setSpeechRate(0.85f)
                isTtsInitialized = true
            }
        }

        // Initialize Sensors
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE_UNCALIBRATED)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
        proximitySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        lightSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_LIGHT)

        proximitySensor?.let {
            proximityMaxRange = it.maximumRange
        }

        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HARDWARE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Test 5: TTS Speech
                "speakDigits" -> {
                    val digits = call.argument<String>("digits") ?: ""
                    val spokenText = digits.toCharArray().joinToString(separator = ", ")
                    if (isTtsInitialized && tts != null) {
                        tts?.speak(spokenText, TextToSpeech.QUEUE_FLUSH, null, "DIGITS_TTS")
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "speakText" -> {
                    val text = call.argument<String>("text") ?: ""
                    if (text.isNotEmpty()) {
                        if (isTtsInitialized && tts != null) {
                            tts?.stop()
                            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NAV_TTS")
                            result.success(true)
                        } else {
                            pendingTtsText = text
                            if (tts == null) {
                                tts = TextToSpeech(this) { status ->
                                    if (status == TextToSpeech.SUCCESS) {
                                        tts?.language = Locale.US
                                        tts?.setSpeechRate(0.95f)
                                        isTtsInitialized = true
                                        pendingTtsText?.let { pending ->
                                            tts?.speak(pending, TextToSpeech.QUEUE_FLUSH, null, "NAV_TTS")
                                            pendingTtsText = null
                                        }
                                    }
                                }
                            }
                            result.success(true)
                        }
                    } else {
                        result.success(false)
                    }
                }

                // Test 6: Sensors
                "startSensors" -> {
                    registerSensors()
                    result.success(true)
                }
                "stopSensors" -> {
                    unregisterSensors()
                    result.success(true)
                }
                "getSensorReadings" -> {
                    val map = HashMap<String, Any>()
                    map["accelX"] = accelX
                    map["accelY"] = accelY
                    map["accelZ"] = accelZ
                    map["accelCount"] = accelEventsCount

                    map["gyroX"] = gyroX
                    map["gyroY"] = gyroY
                    map["gyroZ"] = gyroZ
                    map["gyroCount"] = gyroEventsCount

                    map["proximityDistance"] = proximityDistance
                    map["proximityMaxRange"] = proximityMaxRange
                    map["proximityCount"] = proximityEventsCount

                    map["lightLux"] = lightLux
                    map["lightCount"] = lightEventsCount

                    map["hasAccel"] = (accelerometer != null)
                    map["hasGyro"] = (gyroscope != null)
                    map["hasProximity"] = (proximitySensor != null)
                    map["hasLight"] = (lightSensor != null)

                    result.success(map)
                }

                // Test 7: Network Test
                "checkWifiConnection" -> {
                    val map = checkWifiConnection()
                    result.success(map)
                }
                "testWifiInternet" -> {
                    executor.execute {
                        val pass = testWifiInternetAccess()
                        mainHandler.post { result.success(pass) }
                    }
                }
                "checkMobileConnection" -> {
                    val map = checkMobileConnection()
                    result.success(map)
                }
                "testMobileInternet" -> {
                    executor.execute {
                        val pass = testMobileInternetAccess()
                        mainHandler.post { result.success(pass) }
                    }
                }

                // Test 8: GPS
                "requestLocationPermission" -> {
                    if (hasLocationPermission()) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                android.Manifest.permission.ACCESS_FINE_LOCATION,
                                android.Manifest.permission.ACCESS_COARSE_LOCATION
                            ),
                            1001
                        )
                    }
                }
                "startGps" -> {
                    startLocationUpdates()
                    result.success(true)
                }
                "stopGps" -> {
                    stopLocationUpdates()
                    result.success(true)
                }
                "getGpsData" -> {
                    val map = HashMap<String, Any>()
                    val loc = lastLocation
                    val isGpsEnabled = locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false
                    val isNetworkLocEnabled = locationManager?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ?: false

                    map["isLocationEnabled"] = isGpsEnabled || isNetworkLocEnabled
                    map["hasPermission"] = hasLocationPermission()

                    if (loc != null) {
                        map["hasLocation"] = true
                        map["latitude"] = loc.latitude
                        map["longitude"] = loc.longitude
                        map["accuracy"] = loc.accuracy.toDouble()
                        map["time"] = loc.time
                        map["updatesCount"] = locationUpdatesCount
                    } else {
                        map["hasLocation"] = false
                    }
                    result.success(map)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun registerSensors() {
        sensorManager?.let { sm ->
            accelerometer?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
            gyroscope?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
            proximitySensor?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
            lightSensor?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
        }
    }

    private fun unregisterSensors() {
        sensorManager?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                accelX = event.values[0]
                accelY = event.values[1]
                accelZ = event.values[2]
                accelEventsCount++
            }
            Sensor.TYPE_GYROSCOPE,
            Sensor.TYPE_GYROSCOPE_UNCALIBRATED -> {
                gyroX = event.values[0]
                gyroY = event.values[1]
                gyroZ = event.values[2]
                gyroEventsCount++
            }
            Sensor.TYPE_GAME_ROTATION_VECTOR -> {
                gyroX = event.values[0] * 2.0f
                gyroY = event.values[1] * 2.0f
                gyroZ = event.values[2] * 2.0f
                gyroEventsCount++
            }
            Sensor.TYPE_PROXIMITY -> {
                proximityDistance = event.values[0]
                proximityEventsCount++
            }
            Sensor.TYPE_LIGHT -> {
                lightLux = event.values[0]
                lightEventsCount++
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // Network Helpers
    private fun checkWifiConnection(): Map<String, Any> {
        val map = HashMap<String, Any>()
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

        var isConnected = false
        var ssid = "Wi-Fi"
        var rssi = -55

        if (cm != null) {
            val networks = cm.allNetworks
            for (network in networks) {
                val caps = cm.getNetworkCapabilities(network)
                if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                    isConnected = true
                    break
                }
            }
        }

        if (wm != null && isConnected) {
            try {
                val info = wm.connectionInfo
                if (info != null) {
                    val rawSsid = info.ssid
                    if (!rawSsid.isNullOrBlank() && rawSsid != "<unknown ssid>") {
                        ssid = rawSsid.replace("\"", "")
                    }
                    rssi = info.rssi
                }
            } catch (_: Exception) {}
        }

        map["connected"] = isConnected
        map["ssid"] = ssid
        map["rssi"] = rssi
        map["wifiEnabled"] = wm?.isWifiEnabled ?: isConnected
        return map
    }

    private fun checkMobileConnection(): Map<String, Any> {
        val map = HashMap<String, Any>()
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager

        // Check if user has mobile data enabled in OS settings
        // Safely catch SecurityException or vendor ROM issues
        val isMobileDataEnabled: Boolean = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                tm?.isDataEnabled ?: true
            } else {
                true
            }
        } catch (_: Exception) {
            true // fallback to checking actual network capabilities
        }

        var isConnected = false
        if (cm != null) {
            // Check active network first
            val activeNet = cm.activeNetwork
            if (activeNet != null) {
                val caps = cm.getNetworkCapabilities(activeNet)
                if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                    isConnected = true
                }
            }

            // If not found in active network, search all networks
            if (!isConnected) {
                val networks = cm.allNetworks
                for (network in networks) {
                    val caps = cm.getNetworkCapabilities(network)
                    if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                        isConnected = true
                        break
                    }
                }
            }
        }

        // If OS explicitly confirmed data is disabled, mark not connected
        if (!isMobileDataEnabled) {
            isConnected = false
        }

        map["connected"] = isConnected
        return map
    }

    // --- Test 7.2: Wi-Fi Internet Access ---
    // Wi-Fi Internet Test -> Select TRANSPORT_WIFI network -> Send HTTPS request using Wi-Fi -> Return PASS / FAIL
    private fun testWifiInternetAccess(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false

        // 1. Select TRANSPORT_WIFI network
        var wifiNetwork: Network? = null

        // Check if active network is Wi-Fi
        val activeNet = cm.activeNetwork
        if (activeNet != null) {
            val caps = cm.getNetworkCapabilities(activeNet)
            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                wifiNetwork = activeNet
            }
        }

        // Search all networks for TRANSPORT_WIFI
        if (wifiNetwork == null) {
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network)
                if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                    wifiNetwork = network
                    break
                }
            }
        }

        if (wifiNetwork == null) {
            return false
        }

        // 2. Send HTTPS request strictly bound to the Wi-Fi network
        return executeHttpsProbeOnNetwork(wifiNetwork)
    }

    // --- Test 7.4: Mobile Data Internet Access ---
    // Mobile Data Internet Test -> Select TRANSPORT_CELLULAR network -> Send HTTPS request using cellular data -> Return PASS / FAIL
    private fun testMobileInternetAccess(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager

        // Verify mobile data is enabled in OS settings
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (tm != null && !tm.isDataEnabled) {
                    return false
                }
            }
        } catch (_: Exception) {}

        // 1. Select TRANSPORT_CELLULAR network
        var cellularNetwork: Network? = null

        // Check if active network is Cellular
        val activeNet = cm.activeNetwork
        if (activeNet != null) {
            val caps = cm.getNetworkCapabilities(activeNet)
            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                cellularNetwork = activeNet
            }
        }

        var activeCallback: ConnectivityManager.NetworkCallback? = null

        // When Wi-Fi is active, Android puts cellular transport in standby.
        // We explicitly request the TRANSPORT_CELLULAR network from Android to bring up cellular routing.
        if (cellularNetwork == null) {
            val syncLatch = java.util.concurrent.CountDownLatch(1)
            var acquiredNetwork: Network? = null

            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    acquiredNetwork = network
                    syncLatch.countDown()
                }

                override fun onUnavailable() {
                    syncLatch.countDown()
                }
            }
            activeCallback = callback

            try {
                cm.requestNetwork(request, callback, 4000)
                syncLatch.await(4200, java.util.concurrent.TimeUnit.MILLISECONDS)
                cellularNetwork = acquiredNetwork
            } catch (_: Exception) {}
        }

        // Fallback: Check allNetworks for TRANSPORT_CELLULAR
        if (cellularNetwork == null) {
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network)
                if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                    cellularNetwork = network
                    break
                }
            }
        }

        if (cellularNetwork == null) {
            activeCallback?.let { try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {} }
            return false
        }

        // 2. Send HTTPS request strictly bound to the Cellular network
        val passed = executeHttpsProbeOnNetwork(cellularNetwork)

        activeCallback?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (_: Exception) {}
        }

        return passed
    }

    private fun executeHttpsProbeOnNetwork(network: Network): Boolean {
        val endpoints = listOf(
            "https://www.google.com/generate_204",
            "https://1.1.1.1"
        )

        for (endpoint in endpoints) {
            try {
                val url = URL(endpoint)
                val connection = network.openConnection(url) as HttpURLConnection
                connection.connectTimeout = 3000
                connection.readTimeout = 3000
                connection.instanceFollowRedirects = true
                connection.setRequestProperty("User-Agent", "Mozilla/5.0")
                connection.requestMethod = "GET"
                connection.connect()
                val code = connection.responseCode
                connection.disconnect()
                if (code in 200..399) {
                    return true
                }
            } catch (_: Exception) {
                // Try next endpoint or fail
            }
        }
        return false
    }

    // Location & GPS Helpers
    private fun hasLocationPermission(): Boolean {
        val fine = ActivityCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = ActivityCompat.checkSelfPermission(this, android.Manifest.permission.ACCESS_COARSE_LOCATION)
        return fine == PackageManager.PERMISSION_GRANTED || coarse == PackageManager.PERMISSION_GRANTED
    }

    private fun requestLocationPermissionsIfNeeded() {
        if (!hasLocationPermission()) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                1001
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun startLocationUpdates() {
        if (!hasLocationPermission()) {
            requestLocationPermissionsIfNeeded()
            return
        }

        try {
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            for (provider in providers) {
                if (locationManager?.isProviderEnabled(provider) == true) {
                    val lastKnown = locationManager?.getLastKnownLocation(provider)
                    if (lastKnown != null && (lastLocation == null || lastKnown.time > lastLocation!!.time)) {
                        lastLocation = lastKnown
                    }
                    locationManager?.requestLocationUpdates(provider, 1000L, 0.5f, this)
                }
            }
        } catch (_: SecurityException) {}
    }

    private fun stopLocationUpdates() {
        try {
            locationManager?.removeUpdates(this)
        } catch (_: SecurityException) {}
    }

    override fun onLocationChanged(location: Location) {
        lastLocation = location
        locationUpdatesCount++
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val granted = grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onDestroy() {
        pendingPermissionResult = null
        executor.shutdown()
        tts?.stop()
        tts?.shutdown()
        unregisterSensors()
        stopLocationUpdates()
        super.onDestroy()
    }
}
