package com.carusto.ReactNativePjSip;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import com.facebook.react.bridge.*;

public class PjSipModule extends ReactContextBaseJavaModule {

    private static PjSipBroadcastReceiver receiver;

    public PjSipModule(ReactApplicationContext context) {
        super(context);

        // Module could be started several times, but we have to register receiver only once.
        if (receiver == null) {
            receiver = new PjSipBroadcastReceiver(context);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                this.getReactApplicationContext().registerReceiver(receiver, receiver.getFilter(), Context.RECEIVER_EXPORTED);
            } else {
                this.getReactApplicationContext().registerReceiver(receiver, receiver.getFilter());
            }
        } else {
            receiver.setContext(context);
        }
    }

    @Override
    public String getName() {
        return "PjSipModule";
    }

    @ReactMethod
    public void start(ReadableMap configuration, Callback callback) {
        int id = receiver.register(callback);
        Intent intent = PjActions.createStartIntent(id, configuration, getReactApplicationContext());

        start(intent);
    }

    @ReactMethod void stop(Callback callback) {
        int id = receiver.register(callback);
        Intent intent = PjActions.createStopIntent(id, getReactApplicationContext());

        start(intent);
    }

    @ReactMethod void reconnect(Callback callback) {
        // TODO: implement this method
    }

    @ReactMethod
    public void isStarted(Callback callback) {
        int id = receiver.register(callback);
        Intent intent = PjActions.createCheckIfStartedIntent(id, getReactApplicationContext());

        start(intent);
    }

    @ReactMethod
    public void getCodecs(Callback callback) {
        // TODO: implement this method
//        callback.invoke();
    }

    @ReactMethod
    public void logMessage(ReadableMap message, Callback callback) {
        // TODO: implement this method
    }

    @ReactMethod
    public void getLogsFilePathUrl(Callback callback) {
        int id = receiver.register(callback);
        Intent intent = PjActions.createGetLogsFilePathUrl(id, getReactApplicationContext());

        start(intent);
    }

    @ReactMethod
    public void changeServiceConfiguration(ReadableMap configuration, Callback callback) {
        int id = receiver.register(callback);
        Intent intent = PjActions.createSetServiceConfigurationIntent(id, configuration, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void setAccountCreds(ReadableMap creds, Callback callback) {
        Intent intent = PjActions.createSetAccountCredsIntent(creds, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void registerExistingAccountIfNeeded() {
        // TODO: implement this
    }

    public void getCurrentAccount(Callback callback) {
        // TODO: implement this
    }

    @ReactMethod
    public void makeCall(int accountId, String destination, ReadableMap callSettings, ReadableMap msgData,  Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createMakeCallIntent(callbackId, accountId, destination, callSettings, msgData, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void hangupCall(int callId, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createHangupCallIntent(callbackId, callId, getReactApplicationContext());
        start(intent);
    }

    // TODO: update intCallId to params
    @ReactMethod
    public void declineCall(ReadableMap callSettings, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createDeclineCallIntent(callbackId, callSettings, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void answerCall(int callId, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createAnswerCallIntent(callbackId, callId, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void holdCall(int callId, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createHoldCallIntent(callbackId, callId, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void unholdCall(int callId, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createUnholdCallIntent(callbackId, callId, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void muteCall(int callId, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createMuteCallIntent(callbackId, callId, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void unMuteCall(int callId, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createUnMuteCallIntent(callbackId, callId, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void useSpeaker(int callId, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createUseSpeakerCallIntent(callbackId, callId, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void useEarpiece(int callId, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createUseEarpieceCallIntent(callbackId, callId, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void xferCall(int callId, String destination, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createXFerCallIntent(callbackId, callId, destination, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void xferReplacesCall(int callId, int destCallId, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createXFerReplacesCallIntent(callbackId, callId, destCallId, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void redirectCall(int callId, String destination, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createRedirectCallIntent(callbackId, callId, destination, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void dtmfCall(int callId, String digits, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createDtmfCallIntent(callbackId, callId, digits, getReactApplicationContext());
        start(intent);
    }

    @ReactMethod
    public void changeCodecSettings(ReadableMap codecSettings, Callback callback) {
        int callbackId = receiver.register(callback);
        Intent intent = PjActions.createChangeCodecSettingsIntent(callbackId, codecSettings, getReactApplicationContext());
        start(intent);
    }

    private static final String TAG = "PjSipModule";

    private void start(Intent intent) {
        boolean isRunning = isServiceRunning(getReactApplicationContext(), PjSipService.class);

        getReactApplicationContext().startService(intent);

        if (isRunning) {
            return;
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }

        // we need to bind service on android O so it won't die in background
        getReactApplicationContext().bindService(intent, new ServiceConnection() {
            @Override
            public void onServiceConnected(ComponentName name, IBinder service) {
            }
            @Override
            public void onServiceDisconnected(ComponentName name) {
            }
        }, Context.BIND_AUTO_CREATE);
    }

    public static boolean isServiceRunning(Context context, Class<?> serviceClass) {
        ActivityManager activityManager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        for (ActivityManager.RunningServiceInfo service : activityManager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClass.getName().equals(service.service.getClassName())) {
                return true;
            }
        }
        return false;
    }
}
