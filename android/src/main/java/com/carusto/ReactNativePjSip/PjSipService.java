package com.carusto.ReactNativePjSip;

import static org.pjsip.pjsua2.pj_constants_.PJ_FALSE;
import static org.pjsip.pjsua2.pj_constants_.PJ_SUCCESS;
import static org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_OK;
import static org.pjsip.pjsua2.pjsua_stun_use.PJSUA_STUN_RETRY_ON_FAILURE;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.AudioDeviceInfo;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.net.wifi.WifiManager;
import android.os.Binder;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.Process;
import android.os.Bundle;
import android.telephony.TelephonyManager;
import android.util.Log;

import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import com.carusto.ReactNativePjSip.dto.AccountConfigurationDTO;
import com.carusto.ReactNativePjSip.dto.CallSettingsDTO;
import com.carusto.ReactNativePjSip.dto.ServiceConfigurationDTO;
import com.carusto.ReactNativePjSip.dto.SipMessageDTO;
import com.carusto.ReactNativePjSip.utils.ArgumentUtils;

import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;
import org.json.JSONObject;
import org.pjsip.pjsua2.AccountConfig;
import org.pjsip.pjsua2.AudDevManager;
import org.pjsip.pjsua2.AuthCredInfo;
import org.pjsip.pjsua2.CallInfo;
import org.pjsip.pjsua2.CallOpParam;
import org.pjsip.pjsua2.CallSetting;
import org.pjsip.pjsua2.CodecInfoVector2;
import org.pjsip.pjsua2.Endpoint;
import org.pjsip.pjsua2.EpConfig;
import org.pjsip.pjsua2.OnCallStateParam;
import org.pjsip.pjsua2.OnRegStateParam;
import org.pjsip.pjsua2.SipHeader;
import org.pjsip.pjsua2.SipHeaderVector;
import org.pjsip.pjsua2.SipTxOption;
import org.pjsip.pjsua2.StringVector;
import org.pjsip.pjsua2.ToneDigit;
import org.pjsip.pjsua2.ToneDigitVector;
import org.pjsip.pjsua2.ToneGenerator;
import org.pjsip.pjsua2.TransportConfig;
import org.pjsip.pjsua2.CodecInfo;
import org.pjsip.pjsua2.pj_qos_type;
import org.pjsip.pjsua2.pjsip_inv_state;
import org.pjsip.pjsua2.pjsip_status_code;
import org.pjsip.pjsua2.pjsip_transport_type_e;
import org.pjsip.pjsua2.pjsua_state;

import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;

import kotlin.Unit;
import kotlin.jvm.functions.Function0;

public class PjSipService extends Service {

    private static String TAG = "PjSipService";

    public PjSipEndpointController epController;

    private final IBinder binder = new LocalBinder();

    // Class used for the client Binder.
    public class LocalBinder extends Binder {
        public PjSipService getService() {
            // Return this instance of PjsipHandlerService so clients can call public methods
            return PjSipService.this;
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    // Optionally, you may override onUnbind or onRebind if needed.
    @Override
    public boolean onUnbind(Intent intent) {
        return super.onUnbind(intent);
    }

    @Override
    public int onStartCommand(final Intent intent, int flags, int startId) {
        if (epController == null) {
            epController = new PjSipEndpointController(this, getApplicationContext());
        }

        if (intent != null && intent.hasExtra("foreground")) {
            startForegroundService();
        }

        if (intent != null && intent.hasExtra("audio_focus")) {
            requestMicPermissionsAndFocus(this);
        }

        return epController.handleStartCommandIntentWhenUsingWithService(intent);
    }

    private void startForegroundService() {
        Log.d(TAG, "will start foreground service");

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    "sip_channel",
                    "SIP Calls",
                    NotificationManager.IMPORTANCE_HIGH
            );
            channel.setDescription("Ongoing SIP calls");
            NotificationManager manager = getSystemService(NotificationManager.class);
            manager.createNotificationChannel(channel);
        }

        // Build a notification for the foreground service
        Notification notification = new NotificationCompat.Builder(this, "sip_channel")
                .setContentTitle("Call in progress")
                .setContentText("Connected")
                .setSmallIcon(androidx.autofill.R.drawable.autofill_inline_suggestion_chip_background)  // Ensure you have this drawable
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_CALL) // Uncomment this
                .setOngoing(true) // Prevent dismissal
                .build();

        // Promote the service to foreground
        startForeground(1, notification);
    }

    @Override
    public void onDestroy() {
        if (epController != null) {
            epController.handleDestroyWhenUsingWithService();
            epController = null;
        }

        Log.d(TAG, "on destroy");
        super.onDestroy();
    }

    public static void requestMicPermissionsAndFocus(Context context) {
        // First, check if the RECORD_AUDIO permission is granted.
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "RECORD_AUDIO permission is not granted! " +
                    "Please request it from an Activity before starting the service.");
            // You can also choose to notify your user or end the call flow gracefully.
            return;
        }

        // Obtain the AudioManager from the application context.
        AudioManager audioManager = (AudioManager) context.getApplicationContext()
                .getSystemService(Context.AUDIO_SERVICE);

        // Request audio focus.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // For API 26 and above, build an AudioFocusRequest.
            AudioAttributes audioAttributes = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build();

            AudioFocusRequest focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(audioAttributes)
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener(new AudioManager.OnAudioFocusChangeListener() {
                        @Override
                        public void onAudioFocusChange(int focusChange) {
                            // Handle focus changes as needed.
                            switch (focusChange) {
                                case AudioManager.AUDIOFOCUS_GAIN:
                                    Log.d(TAG, "Audio focus gained");
                                    break;
                                case AudioManager.AUDIOFOCUS_LOSS:
                                    Log.d(TAG, "Audio focus lost permanently");
                                    break;
                                case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                                    Log.d(TAG, "Audio focus lost transiently");
                                    break;
                                case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
                                    Log.d(TAG, "Audio focus lost transiently, can duck");
                                    break;
                                default:
                                    Log.d(TAG, "Audio focus changed: " + focusChange);
                            }
                        }
                    })
                    .build();

            int result = audioManager.requestAudioFocus(focusRequest);
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                Log.d(TAG, "Audio focus granted");
                // Set audio mode for voice communication.
                audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
            } else {
                Log.w(TAG, "Audio focus NOT granted");
            }
        } else {
            // For devices below API 26, use the legacy API.
            int result = audioManager.requestAudioFocus(new AudioManager.OnAudioFocusChangeListener() {
                @Override
                public void onAudioFocusChange(int focusChange) {
                    Log.d(TAG, "Audio focus changed: " + focusChange);
                }
            }, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT);
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                Log.d(TAG, "Audio focus granted (legacy)");
                audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
            } else {
                Log.w(TAG, "Audio focus NOT granted (legacy)");
            }
        }
    }
}
