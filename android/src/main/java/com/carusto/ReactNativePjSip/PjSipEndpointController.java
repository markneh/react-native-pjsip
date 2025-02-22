package com.carusto.ReactNativePjSip;

import static android.app.Service.START_NOT_STICKY;
import static android.app.Service.START_STICKY;
import static android.content.Context.AUDIO_SERVICE;
import static android.content.Context.POWER_SERVICE;
import static org.pjsip.pjsua2.pj_constants_.PJ_FALSE;
import static org.pjsip.pjsua2.pj_constants_.PJ_SUCCESS;
import static org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_OK;
import static org.pjsip.pjsua2.pjsua_stun_use.PJSUA_STUN_RETRY_ON_FAILURE;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioAttributes;
import android.media.AudioDeviceInfo;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.PowerManager;
import android.os.Process;
import android.telephony.TelephonyManager;
import android.util.Log;

import com.carusto.ReactNativePjSip.dto.AccountConfigurationDTO;
import com.carusto.ReactNativePjSip.dto.CallSettingsDTO;
import com.carusto.ReactNativePjSip.dto.ServiceConfigurationDTO;
import com.carusto.ReactNativePjSip.dto.SipMessageDTO;
import com.carusto.ReactNativePjSip.utils.ArgumentUtils;

import org.jetbrains.annotations.Nullable;
import org.json.JSONObject;
import org.pjsip.pjsua2.AccountConfig;
import org.pjsip.pjsua2.AudDevManager;
import org.pjsip.pjsua2.AuthCredInfo;
import org.pjsip.pjsua2.CallInfo;
import org.pjsip.pjsua2.CallOpParam;
import org.pjsip.pjsua2.CallSetting;
import org.pjsip.pjsua2.CodecInfo;
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
import org.pjsip.pjsua2.pj_qos_type;
import org.pjsip.pjsua2.pjsip_inv_state;
import org.pjsip.pjsua2.pjsip_status_code;
import org.pjsip.pjsua2.pjsip_transport_type_e;
import org.pjsip.pjsua2.pjsua_state;

import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;

public class PjSipEndpointController {

    private static String TAG = "PjSipEndpointController";

    private boolean mInitialized;

    private HandlerThread mWorkerThread;

    private Handler mHandler;

    private Endpoint mEndpoint;

    private int mUdpTransportId;

    private int mTcpTransportId;

    private int mTlsTransportId;

    private ToneGenerator mToneGenerator;

    private ServiceConfigurationDTO mServiceConfiguration = new ServiceConfigurationDTO();

    private PjSipLogWriter mLogWriter;

    private PjSipBroadcastEmiter mEmitter;

    private PjSipAccount mAccount;

    private List<PjSipCall> mCalls = new ArrayList<>();

    // In order to ensure that GC will not destroy objects that are used in PJSIP
    // Also there is limitation of pjsip that thread should be registered first before working with library
    // (but we couldn't register GC thread in pjsip)
    private List<Object> mTrash = new LinkedList<>();

    private AudioManager mAudioManager;

    private boolean mUseSpeaker = false;

    private PowerManager mPowerManager;

    private PowerManager.WakeLock mIncallWakeLock;

    private TelephonyManager mTelephonyManager;

    private WifiManager mWifiManager;

    private WifiManager.WifiLock mWifiLock;

    private boolean mGSMIdle;

    private BroadcastReceiver mPhoneStateChangedReceiver = new PjSipEndpointController.PhoneStateChangedReceiver();

    private Intent mPendingAccountConfigurationIntent;

    public PjSipBroadcastEmiter getEmitter() {
        return mEmitter;
    }

    public @Nullable List<PjSipCall> getCurrentCalls() {
        return mCalls;
    }

    private Context context;
    private Context appContext;

    public Context getContext() {
        return context;
    }

    public PjSipEndpointController(Context context, Context appContext) {
        this.context = context;
        this.appContext = appContext;
    }

    public int handleStartCommandIntentWhenUsingWithService(Intent intent) {
        if (intent == null) {
            return START_STICKY;
        }

        handleIntent(intent);

        return START_NOT_STICKY;
    }

    public void handleIntent(Intent intent) {
        if (!mInitialized) {
            performInit(intent);
        }

        String action = intent.getAction();
        boolean isStartIntent = action != null && action.equals(PjActions.ACTION_START);

        if (action != null && action.equals(PjActions.ACTION_CHECK_IF_STARTED)) {
            handleCheckIfStartedIntent(intent);
        } else if (isStartIntent && isStarted()) {
            List<PjSipAccount> mAccounts = new ArrayList<PjSipAccount>();
            if (mAccount != null) {
                mAccounts.add(mAccount);
            }
            job(() -> {
                mEmitter.fireStarted(intent, mAccounts, mCalls, getCodecsAsJson());
            });
        } else if (isStartIntent) {
            job(() -> initEndpoint(intent));
        } else {
            job(() -> handle(intent));
        }
    }

    public void handleDestroyWhenUsingWithService() {
        Runtime.getRuntime().gc();

        job(() -> {
            try {
                destroyEndpoint();
            } catch (Exception e) {
                e.printStackTrace();
            }
        });

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            Log.d(TAG, "Quiting worker thread safely");
            mWorkerThread.quitSafely();
        }

        context.unregisterReceiver(mPhoneStateChangedReceiver);
    }

    private void initEndpoint(Intent startIntent) {
        // Load native libraries

        try {
            System.loadLibrary("pjsua2");
        } catch (UnsatisfiedLinkError error) {
            Log.e(TAG, "Error while loading PJSIP pjsua2 native library", error);
            handleStart(startIntent, new RuntimeException(error));
            return;
        }

        // Start stack
        try {

            // remove current account just to be safe
            evictCurrentAccountIfNeeded();
            Runtime.getRuntime().gc();

            mEndpoint = new Endpoint();
            mEndpoint.libCreate();


            // Configure endpoint
            EpConfig epConfig = new EpConfig();

            epConfig.getLogConfig().setLevel(5);
            epConfig.getLogConfig().setConsoleLevel(4);


            mLogWriter = new PjSipLogWriter(appContext);
            epConfig.getLogConfig().setWriter(mLogWriter);


            if (startIntent != null && startIntent.hasExtra("service")) {
                mServiceConfiguration = ServiceConfigurationDTO.fromMap((Map) startIntent.getSerializableExtra("service"));
            }

            if (mServiceConfiguration.isUserAgentNotEmpty()) {
                epConfig.getUaConfig().setUserAgent(mServiceConfiguration.getUserAgent());
            }

            if (mServiceConfiguration.isStunServersNotEmpty()) {
                epConfig.getUaConfig().setStunServer(mServiceConfiguration.getStunServers());
            }

            epConfig.getMedConfig().setHasIoqueue(true);
            epConfig.getMedConfig().setClockRate(8000);
            epConfig.getMedConfig().setQuality(4);
            epConfig.getMedConfig().setEcOptions(1);
            epConfig.getMedConfig().setEcTailLen(200);
            epConfig.getMedConfig().setThreadCnt(2);
            mEndpoint.libInit(epConfig);

            mTrash.add(epConfig);

            // Configure transports
            {
                TransportConfig transportConfig = new TransportConfig();
                transportConfig.setQosType(pj_qos_type.PJ_QOS_TYPE_VOICE);
                mUdpTransportId = mEndpoint.transportCreate(pjsip_transport_type_e.PJSIP_TRANSPORT_UDP, transportConfig);
                mTrash.add(transportConfig);
            }
            {
                TransportConfig transportConfig = new TransportConfig();
                transportConfig.setQosType(pj_qos_type.PJ_QOS_TYPE_VOICE);
                mTcpTransportId = mEndpoint.transportCreate(pjsip_transport_type_e.PJSIP_TRANSPORT_TCP, transportConfig);
                mTrash.add(transportConfig);
            }
            {
                TransportConfig transportConfig = new TransportConfig();
                transportConfig.setQosType(pj_qos_type.PJ_QOS_TYPE_VOICE);
                mTlsTransportId = mEndpoint.transportCreate(pjsip_transport_type_e.PJSIP_TRANSPORT_TLS, transportConfig);
                mTrash.add(transportConfig);
            }

            mEndpoint.libStart();
            mEndpoint.libRegisterThread(mWorkerThread.getName());

            requestMicPermissions();

            handleStart(startIntent, null);
            emmitLaunchStatusUpdateEvent();
        } catch (Exception e) {
            Log.e(TAG, "Error while starting PJSIP", e);
            handleStart(startIntent, e);
            emmitLaunchStatusUpdateEvent();
        }
    }

//    private void requestMicPermissions() {
//       AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
//        audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
//
//        // Build the AudioFocusRequest
//        AudioFocusRequest focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
//                .setAudioAttributes(new AudioAttributes.Builder()
//                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
//                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
//                        .build())
//                .setOnAudioFocusChangeListener(new AudioManager.OnAudioFocusChangeListener() {
//                    @Override
//                    public void onAudioFocusChange(int focusChange) {
//                        // Handle audio focus changes if needed
//                        Log.d(TAG, "Audio focus changed: " + focusChange);
//                    }
//                })
//                .build();
//
//        // Request audio focus
//        int result = audioManager.requestAudioFocus(
//                null,
//                AudioManager.STREAM_VOICE_CALL,
//                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT);
//        if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
//            Log.d(TAG, "Audio focus granted");
//        } else {
//            Log.w(TAG, "Audio focus NOT granted");
//        }
//    }

    private void requestMicPermissions() {
//        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
//
//        // Ensure you have the MODIFY_AUDIO_SETTINGS permission declared in the manifest.
//        audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
//
//        // Build the AudioFocusRequest with appropriate AudioAttributes.
//        AudioFocusRequest focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
//                .setAudioAttributes(new AudioAttributes.Builder()
//                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
//                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
//                        .build())
//                .setOnAudioFocusChangeListener(new AudioManager.OnAudioFocusChangeListener() {
//                    @Override
//                    public void onAudioFocusChange(int focusChange) {
//                        // Handle audio focus changes if needed
//                        Log.d(TAG, "Audio focus changed: " + focusChange);
//                    }
//                })
//                .build();
//
//        // Request audio focus using the built AudioFocusRequest.
//        int result = audioManager.requestAudioFocus(focusRequest);
//        if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
//            Log.d(TAG, "Audio focus granted");
//        } else {
//            Log.w(TAG, "Audio focus NOT granted");
//        }
    }

    private boolean isStarted() {
        if (mEndpoint == null) {
            return false;
        }

        return mEndpoint.libGetState() == pjsua_state.PJSUA_STATE_RUNNING;
    }

    private void performInit(Intent intent) {
        mWorkerThread = new HandlerThread(getClass().getSimpleName(), Process.THREAD_PRIORITY_FOREGROUND);
        mWorkerThread.setPriority(Thread.MAX_PRIORITY);
        mWorkerThread.start();
        mHandler = new Handler(mWorkerThread.getLooper());
        mEmitter = new PjSipBroadcastEmiter(context);
        mAudioManager = (AudioManager) appContext.getSystemService(AUDIO_SERVICE);
        mPowerManager = (PowerManager) appContext.getSystemService(POWER_SERVICE);
        mWifiManager = (WifiManager) appContext.getSystemService(Context.WIFI_SERVICE);
        mWifiLock = mWifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, context.getPackageName() + "-wifi-call-lock");
        mWifiLock.setReferenceCounted(false);
        mTelephonyManager = (TelephonyManager) appContext.getSystemService(Context.TELEPHONY_SERVICE);
        mGSMIdle = mTelephonyManager.getCallState() == TelephonyManager.CALL_STATE_IDLE;

        IntentFilter phoneStateFilter = new IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED);
        context.registerReceiver(mPhoneStateChangedReceiver, phoneStateFilter);

        mInitialized = true;
    }

    private void destroyEndpoint() throws Exception {
        mPendingAccountConfigurationIntent = null;

        if (mEndpoint == null) {
            Log.d(TAG, "Attempt to destroy endpoint but none was initialized");
            emmitLaunchStatusUpdateEvent();
            return;
        }

        mEndpoint.libDestroy();
        mEndpoint.delete();
        mEndpoint = null;

        emmitLaunchStatusUpdateEvent();
    }

    private void job(Runnable job) {
        if (mHandler != null) {
            mHandler.post(job);
        }
    }

    protected synchronized AudDevManager getAudDevManager() {
        return mEndpoint.audDevManager();
    }

    public void evictCurrentAccountIfNeeded() {
        if (mHandler.getLooper().getThread() != Thread.currentThread()) {
            job(new Runnable() {
                @Override
                public void run() {
                    evictCurrentAccountIfNeeded();
                }
            });
            return;
        }

        // Remove account in PjSip
        if (mAccount != null) {
            Log.i(TAG, "evictCurrentAccountIfNeeded() -> will remove current account");
            mAccount.delete();
            mAccount = null;
        }
    }

    private void applyPendingCredsIfNeeded() {
        if (mPendingAccountConfigurationIntent != null) {
            Log.i(TAG, "applyPendingCredsIfNeeded() got pending creds -> will update " + mPendingAccountConfigurationIntent.toString());
            handleSetAccountCreds(mPendingAccountConfigurationIntent);
            mPendingAccountConfigurationIntent = null;
        }
    }

    public void evict(final PjSipCall call) {
        if (mHandler.getLooper().getThread() != Thread.currentThread()) {
            job(new Runnable() {
                @Override
                public void run() {
                    evict(call);
                }
            });
            return;
        }

        mCalls.remove(call);
        call.delete();
    }


    private void handle(Intent intent) {
        if (intent == null || intent.getAction() == null) {
            return;
        }

        Log.d(TAG, "Handle \"" + intent.getAction() + "\" action (" + ArgumentUtils.dumpIntentExtraParameters(intent) + ")");

        switch (intent.getAction()) {
            // General actions
            case PjActions.ACTION_STOP:
                handleStopIntent(intent);
                break;
            case PjActions.ACTION_START:
            case PjActions.ACTION_CHECK_IF_STARTED:
                // this will be handled in onStart method
                break;

            // Account actions
            case PjActions.ACTION_SET_CREDS:
                handleSetAccountCreds(intent);
                break;
            case PjActions.ACTION_GET_ACCOUNT:
                handleGetCurrentAccountIntent(intent);
                break;

            // Call actions
            case PjActions.ACTION_MAKE_CALL:
                handleCallMake(intent);
                break;
            case PjActions.ACTION_HANGUP_CALL:
                handleCallHangup(intent);
                break;
            case PjActions.ACTION_DECLINE_CALL:
                handleCallDecline(intent);
                break;
            case PjActions.ACTION_ANSWER_CALL:
                handleCallAnswer(intent);
                break;
            case PjActions.ACTION_HOLD_CALL:
                handleCallSetOnHold(intent);
                break;
            case PjActions.ACTION_UNHOLD_CALL:
                handleCallReleaseFromHold(intent);
                break;
            case PjActions.ACTION_MUTE_CALL:
                handleCallMute(intent);
                break;
            case PjActions.ACTION_UNMUTE_CALL:
                handleCallUnMute(intent);
                break;
            case PjActions.ACTION_USE_SPEAKER_CALL:
                handleCallUseSpeaker(intent);
                break;
            case PjActions.ACTION_USE_EARPIECE_CALL:
                handleCallUseEarpiece(intent);
                break;
            case PjActions.ACTION_XFER_CALL:
                handleCallXFer(intent);
                break;
            case PjActions.ACTION_XFER_REPLACES_CALL:
                handleCallXFerReplaces(intent);
                break;
            case PjActions.ACTION_REDIRECT_CALL:
                handleCallRedirect(intent);
                break;
            case PjActions.ACTION_DTMF_CALL:
                handleCallDtmf(intent);
                break;
            case PjActions.ACTION_CHANGE_CODEC_SETTINGS:
                handleChangeCodecSettings(intent);
                break;
            case PjActions.ACTION_GET_LOG_FILE_URL:
                handleGetLogsFileUrl(intent);
                break;

            // Configuration actions
            case PjActions.ACTION_SET_SERVICE_CONFIGURATION:
                handleSetServiceConfiguration(intent);
                break;
        }
    }

    private void handleStart(Intent intent, Exception e) {
        if (e != null) {
            mEmitter.fireIntentHandled(intent, e);
            return;
        }

        // Modify existing configuration if it changes during application reload.
        if (intent.hasExtra("service")) {
            ServiceConfigurationDTO newServiceConfiguration = ServiceConfigurationDTO.fromMap((Map) intent.getSerializableExtra("service"));
            if (!newServiceConfiguration.equals(mServiceConfiguration)) {
                updateServiceConfiguration(newServiceConfiguration);
            }
        }

        applyPendingCredsIfNeeded();

        job(() -> {
            JSONObject codecs = getCodecsAsJson();

            List<PjSipAccount> mAccounts = new ArrayList<PjSipAccount>();
            if (mAccount != null) {
                mAccounts.add(mAccount);
            }

            mEmitter.fireStarted(intent, mAccounts, mCalls, codecs);
        });
    }

    private void handleStopIntent(Intent intent) {
        if (!isStarted()) {
            mEmitter.fireIntentHandled(intent);
            emmitLaunchStatusUpdateEvent();
            return;
        }

        try {
            destroyEndpoint();
            emmitLaunchStatusUpdateEvent();
            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            emmitLaunchStatusUpdateEvent();
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private JSONObject getCodecsAsJson() {
        try {
            CodecInfoVector2 codVect = mEndpoint.codecEnum2();
            JSONObject codecs = new JSONObject();

            for (int i = 0; i < codVect.size(); i++) {
                CodecInfo codInfo = codVect.get(i);
                String codId = codInfo.getCodecId();
                short priority = codInfo.getPriority();
                codecs.put(codId, priority);
                codInfo.delete();
            }

            JSONObject settings = mServiceConfiguration.toJson();
            settings.put("codecs", codecs);

            return settings;
        } catch (Exception error) {
            Log.e(TAG, "Error while building codecs list", error);
            return null;
        }
    }

    private void handleSetServiceConfiguration(Intent intent) {
        try {
            updateServiceConfiguration(ServiceConfigurationDTO.fromIntent(intent));

            // Emmit response
            mEmitter.fireIntentHandled(intent, mServiceConfiguration.toJson());
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void updateServiceConfiguration(ServiceConfigurationDTO configuration) {
        mServiceConfiguration = configuration;
    }

    private void handleSetAccountCreds(Intent intent) {
        AccountConfigurationDTO accountConfiguration = AccountConfigurationDTO.fromIntent(intent);

        if (accountConfiguration == null) {
            Log.i(TAG, "handleSetAccountCreds() config is null -> will remove account");
            evictCurrentAccountIfNeeded();
            return;
        }

        if (!isStarted()) {
            Log.i(TAG, "handleSetAccountCreds() pjsip is not started -> will set pending account config");
            mPendingAccountConfigurationIntent = intent;
            return;
        }

        if (mAccount == null) {
            Log.i(TAG, "handleSetAccountCreds() no account yet -> will try to create account");

            try {
                mAccount = doAccountCreate(accountConfiguration);
                Log.i(TAG, "handleSetAccountCreds() successfully created an account");
                mEmitter.fireAccountCreated(intent, mAccount);
            } catch (Exception e) {
                Log.e(TAG, "handleSetAccountCreds() failed to create an account", e);
                mEmitter.fireIntentHandled(intent, e);
            }
            return;
        }

        Log.d(TAG, "handleSetAccountCreds() account exists -> will check if account needs to be update");

        boolean shouldUpdateAccount = mAccount.shouldUpdateConfiguration(accountConfiguration);
        if (!shouldUpdateAccount) {
            Log.d(TAG, "handleSetAccountCreds() config didn't change -> won't proceed with updates");
            return;
        }

        boolean isWaitingForRegResult = mAccount.isRegInProgress();
        boolean hasCall = !mCalls.isEmpty();

        if (hasCall || isWaitingForRegResult) {
            Log.d(TAG, "handleSetAccountCreds() can't update account yet -> there's a call or process of registered previous config is not finished yet");
            mPendingAccountConfigurationIntent = intent;
        } else {
            // TODO: think about this
//            if (self.udpTransportId == PJSUA_INVALID_ID || [self.account lastRegError] == PJSIP_SC_SERVICE_UNAVAILABLE) {
//                logDebugMessage(PjSipEndpointLogTypeInfo, @"[setAccountCreds:]", @"upd is down or last reg error is 503 -> will restart udp");
//            [self restartUDP];
//            }
//
            Log.d(TAG, "handleSetAccountCreds() account exists -> will update account");
//            mAccount.updateAccount(accountConfiguration);
            try {
                doAccountUpdate(accountConfiguration);
                Log.i(TAG, "handleSetAccountCreds() successfully update account");
            } catch (Exception e) {
                Log.e(TAG, "handleSetAccountCreds() failed to update account: ", e);
            }
        }
    }

    private PjSipAccount doAccountCreate(AccountConfigurationDTO configuration) throws Exception {
        int transportId = transportIdForConfiguration(configuration);
        AccountConfig cfg = accountConfigFromConfiguration(configuration, transportId);

        PjSipAccount account = new PjSipAccount(this, transportId, configuration);
        account.create(cfg);

        return account;
    }

    private void doAccountUpdate(AccountConfigurationDTO configuration) throws Exception {
        if (mAccount == null) {
            Log.w(TAG, "doAccountUpdate() attempt to update account configuration but no account exists");
            return;
        }

        int transportId = transportIdForConfiguration(configuration);
        AccountConfig cfg = accountConfigFromConfiguration(configuration, transportId);

        mAccount.modify(cfg);
    }

    private int transportIdForConfiguration(AccountConfigurationDTO configuration) {
        if (configuration.isTransportNotEmpty()) {
            switch (configuration.getTransport()) {
                case "UDP":
                    return mUdpTransportId;
                case "TLS":
                    return mTlsTransportId;
                case "TCP":
                default:
                    return mTcpTransportId;
            }
        }

        return mTcpTransportId;
    }

    private AccountConfig accountConfigFromConfiguration(AccountConfigurationDTO configuration, int transportId) {
        AccountConfig cfg = new AccountConfig();

        // General settings
        AuthCredInfo cred = new AuthCredInfo(
                "Digest",
                configuration.getNomalizedRegServer(),
                configuration.getUsername(),
                0,
                configuration.getPassword()
        );

        String idUri = configuration.getIdUri();
        String regUri = configuration.getRegUri();

        cfg.setIdUri(idUri);
        cfg.getRegConfig().setRegistrarUri(regUri);
        cfg.getRegConfig().setRegisterOnAdd(configuration.isRegOnAdd());
        cfg.getSipConfig().getAuthCreds().add(cred);

        cfg.getNatConfig().setUdpKaIntervalSec(0);
        cfg.getNatConfig().setSdpNatRewriteUse(PJ_FALSE);
        cfg.getNatConfig().setSipStunUse(PJSUA_STUN_RETRY_ON_FAILURE);

        cfg.getVideoConfig().setAutoTransmitOutgoing(false);
        cfg.getVideoConfig().setAutoShowIncoming(false);

        // Registration settings

        if (configuration.getContactParams() != null) {
            cfg.getSipConfig().setContactParams(configuration.getContactParams());
        }
        if (configuration.getContactUriParams() != null) {
            cfg.getSipConfig().setContactUriParams(configuration.getContactUriParams());
        }
        if (configuration.getRegContactParams() != null) {
            Log.w(TAG, "Property regContactParams are not supported on android, use contactParams instead");
        }

        if (configuration.getRegHeaders() != null && configuration.getRegHeaders().size() > 0) {
            SipHeaderVector headers = new SipHeaderVector();

            for (Map.Entry<String, String> entry : configuration.getRegHeaders().entrySet()) {
                SipHeader hdr = new SipHeader();
                hdr.setHName(entry.getKey());
                hdr.setHValue(entry.getValue());
                headers.add(hdr);
            }

            cfg.getRegConfig().setHeaders(headers);
        }

        // Transport settings

        cfg.getSipConfig().setTransportId(transportId);

        if (configuration.isProxyNotEmpty()) {
            StringVector v = new StringVector();
            v.add(configuration.getProxy());
            cfg.getSipConfig().setProxies(v);
        }

        cfg.getMediaConfig().getTransportConfig().setQosType(pj_qos_type.PJ_QOS_TYPE_VOICE);

        mTrash.add(cfg);
        mTrash.add(cred);

        return cfg;
    }

    private void handleGetCurrentAccountIntent(Intent intent) {
        try {
            if (mAccount != null) {
                mEmitter.fireIntentHandled(intent, mAccount.toJson());
            } else {
                mEmitter.fireIntentHandled(intent);
            }
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallMake(Intent intent) {
        try {
            if (mAccount == null) {
                Log.w(TAG, "Attempt to perform a call without an account");
                throw new Exception("Attempt to perform a call without an account");
            }

            String destination = intent.getStringExtra("destination");
            String settingsJson = intent.getStringExtra("settings");
            String messageJson = intent.getStringExtra("message");

            // -----
            CallOpParam callOpParam = new CallOpParam(true);

            CallSetting callSettings = new CallSetting();
            callSettings.setVideoCount(0);

            if (settingsJson != null) {
                CallSettingsDTO settingsDTO = CallSettingsDTO.fromJson(settingsJson);

                if (settingsDTO.getAudioCount() != null) {
                    callSettings.setAudioCount(settingsDTO.getAudioCount());
                }

                if (settingsDTO.getFlag() != null) {
                    callSettings.setFlag(settingsDTO.getFlag());
                }
                if (settingsDTO.getRequestKeyframeMethod() != null) {
                    callSettings.setReqKeyframeMethod(settingsDTO.getRequestKeyframeMethod());
                }
            }

            mTrash.add(callSettings);

            if (messageJson != null) {
                SipMessageDTO messageDTO = SipMessageDTO.fromJson(messageJson);
                SipTxOption callTxOption = new SipTxOption();

                if (messageDTO.getTargetUri() != null) {
                    callTxOption.setTargetUri(messageDTO.getTargetUri());
                }
                if (messageDTO.getContentType() != null) {
                    callTxOption.setContentType(messageDTO.getContentType());
                }
                if (messageDTO.getHeaders() != null) {
                    callTxOption.setHeaders(PjSipUtils.mapToSipHeaderVector(messageDTO.getHeaders()));
                }
                if (messageDTO.getBody() != null) {
                    callTxOption.setMsgBody(messageDTO.getBody());
                }

                callOpParam.setTxOption(callTxOption);

                mTrash.add(callTxOption);
            }

            PjSipCall call = new PjSipCall(mAccount);
            Log.d(TAG, "will make call");
            call.makeCall(destination, callOpParam);

            callOpParam.delete();

            // Automatically put other calls on hold.
            doPauseParallelCalls(call);

            mCalls.add(call);
            Log.d(TAG, "will get call info");
            mEmitter.fireIntentHandled(intent, call.toJson());
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallHangup(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);
            PjSipCall call = findCall(callId);
            Log.d(TAG, "hanging up call");
            call.hangup(new CallOpParam(true));

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallDecline(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);

            // -----
            PjSipCall call = findCall(callId);
            CallOpParam prm = new CallOpParam(true);
            prm.setStatusCode(pjsip_status_code.PJSIP_SC_DECLINE);
            Log.d(TAG, "declining call");
            call.hangup(prm);
            prm.delete();

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallAnswer(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);

            // -----
            PjSipCall call = findCall(callId);
            CallOpParam prm = new CallOpParam();
            prm.setStatusCode(PJSIP_SC_OK);
            CallSetting settings = prm.getOpt();
            settings.setVideoCount(0);
            call.answer(prm);

            // Automatically put other calls on hold.
            doPauseParallelCalls(call);

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallSetOnHold(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);

            // -----
            PjSipCall call = findCall(callId);
            call.hold();

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallReleaseFromHold(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);

            // -----
            PjSipCall call = findCall(callId);
            call.unhold();

            // Automatically put other calls on hold.
            doPauseParallelCalls(call);

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallMute(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);

            // -----
            PjSipCall call = findCall(callId);
            call.mute();

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallUnMute(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);

            // -----
            PjSipCall call = findCall(callId);
            call.unmute();

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallUseSpeaker(Intent intent) {
        try {
            setSpeaker(true);

            for (PjSipCall call : mCalls) {
                emmitCallUpdated(call);
            }

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallUseEarpiece(Intent intent) {
        try {
            setSpeaker(false);

            for (PjSipCall call : mCalls) {
                emmitCallUpdated(call);
            }

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallXFer(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);
            String destination = intent.getStringExtra("destination");

            // -----
            PjSipCall call = findCall(callId);
            call.xfer(destination, new CallOpParam(true));

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallXFerReplaces(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);
            int destinationCallId = intent.getIntExtra("dest_call_id", -1);

            // -----
            PjSipCall call = findCall(callId);
            PjSipCall destinationCall = findCall(destinationCallId);
            call.xferReplaces(destinationCall, new CallOpParam(true));

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallRedirect(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);
            String destination = intent.getStringExtra("destination");

            // -----
            PjSipCall call = findCall(callId);
            call.redirect(destination);

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCallDtmf(Intent intent) {
        try {
            int callId = intent.getIntExtra("call_id", -1);
            String digits = intent.getStringExtra("digits");

            // -----
            PjSipCall call = findCall(callId);
            call.dialDtmf(digits);

            mEmitter.fireIntentHandled(intent);

            if (mToneGenerator == null) {
                mToneGenerator = new ToneGenerator();
                mToneGenerator.createToneGenerator();
            }

            if (digits != null) {
                ToneDigitVector digitsVector = new ToneDigitVector();
                ToneDigit digit = new ToneDigit();
                char digitChar = digits.charAt(0);
                digit.setDigit(digitChar);
                digit.setVolume((short) 0);
                digit.setOn_msec((short) 100);
                digit.setOff_msec((short) 500);
                digitsVector.add(digit);
                mToneGenerator.playDigits(digitsVector);
                mToneGenerator.startTransmit(mEndpoint.audDevManager().getPlaybackDevMedia());
            }

        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleChangeCodecSettings(Intent intent) {
        try {
            Bundle codecSettings = intent.getExtras();

            // -----
            if (codecSettings != null) {
                for (String key : codecSettings.keySet()) {

                    if (!key.equals("callback_id")) {

                        short priority = (short) codecSettings.getInt(key);

                        mEndpoint.codecSetPriority(key, priority);

                    }

                }
            }

            mEmitter.fireIntentHandled(intent);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleGetLogsFileUrl(Intent intent) {
        String filename = PjSipUtils.getLogsFilePath(context);

        if (mLogWriter != null) {
            mLogWriter.flush();
        }

        try {
            JSONObject data = new JSONObject();
            data.put("url", filename);
            mEmitter.fireIntentHandled(intent, data);
        } catch (Exception e) {
            e.printStackTrace();
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private void handleCheckIfStartedIntent(Intent intent) {
        try {
            boolean isStarted = isStarted();
            JSONObject data = new JSONObject();
            data.put("is_started", isStarted);
            mEmitter.fireIntentHandled(intent, data);
        } catch (Exception e) {
            mEmitter.fireIntentHandled(intent, e);
        }
    }

    private PjSipAccount findAccount(int id) throws Exception {
        if (mAccount != null && mAccount.getId() == id) {
            return mAccount;
        }

        throw new Exception("Account with specified \"" + id + "\" id not found");
    }

    private PjSipCall findCall(int id) throws Exception {
        for (PjSipCall call : mCalls) {
            if (call.getId() == id) {
                return call;
            }
        }

        throw new Exception("Call with specified \"" + id + "\" id not found");
    }

    void emmitRegistrationChanged(PjSipAccount account, OnRegStateParam prm) {
        getEmitter().fireRegistrationChangeEvent(account, prm);

        if (prm.getCode() == PJSIP_SC_OK && prm.getStatus() == PJ_SUCCESS && prm.getExpiration() > 0) {
            Log.i(TAG, "onRegStateChanged() account did register successfully -> will try to apply pending creds if needed");
            applyPendingCredsIfNeeded();
        }
    }

    void emmitLaunchStatusUpdateEvent() {
        Log.d(TAG, "should emmit status to " + isStarted());
        getEmitter().fireLaunchStatusUpdateEvent(isStarted());
    }

    void emmitMessageReceived(PjSipAccount account, PjSipMessage message) {
        getEmitter().fireMessageReceivedEvent(message);
    }

    void emmitCallReceived(PjSipAccount account, PjSipCall call) {
        // Automatically decline incoming call when user uses GSM
        if (!mGSMIdle) {
            try {
                Log.d(TAG, "TODO: auto hangup of not gsm idle not sure what is going on");
//                call.hangup(new CallOpParam(true));
            } catch (Exception e) {
                Log.w(TAG, "Failed to decline incoming call when user uses GSM", e);
            }

//            return;
        }

        /**
         // Automatically start application when incoming call received.
         if (mAppHidden) {
         try {
         String ns = getApplicationContext().getPackageName();
         String cls = ns + ".MainActivity";

         Intent intent = new Intent(getApplicationContext(), Class.forName(cls));
         intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.EXTRA_DOCK_STATE_CAR);
         intent.addCategory(Intent.CATEGORY_LAUNCHER);
         intent.putExtra("foreground", true);

         startActivity(intent);
         } catch (Exception e) {
         Log.w(TAG, "Failed to open application on received call", e);
         }
         }

         job(new Runnable() {
        @Override public void run() {
        // Brighten screen at least 10 seconds
        PowerManager.WakeLock wl = mPowerManager.newWakeLock(
        PowerManager.ACQUIRE_CAUSES_WAKEUP | PowerManager.ON_AFTER_RELEASE | PowerManager.FULL_WAKE_LOCK,
        "incoming_call"
        );
        wl.acquire(10000);

        if (mCalls.size() == 0) {
        mAudioManager.setSpeakerphoneOn(true);
        }
        }
        });
         **/

        // -----
        mCalls.add(call);

        Log.d(TAG, "will fire call received event");
        mEmitter.fireCallReceivedEvent(call);
    }

    void emmitCallStateChanged(PjSipCall call, OnCallStateParam prm) {
        try {
            Log.d(TAG, "will get info to check state");
            CallInfo info = call.getInfo();
            String callData = call.toJsonString();
            final int callId = call.getId();
            Log.d(TAG, "info state " + info.getState());
            boolean isDisconnected = info.getState() == pjsip_inv_state.PJSIP_INV_STATE_DISCONNECTED;


            job(() -> {
                try {
                    if (isDisconnected) {
                        Log.d(TAG, "will emmit call terminated");
                        emmitCallTerminated(callId, callData, prm);

                        if (mUseSpeaker && mAudioManager.isSpeakerphoneOn()) {
                            setSpeaker(false);
                        }

                        Log.d(TAG, "emmitCallStateChanged() call ended -> will apply pending creds if needed");
                        applyPendingCredsIfNeeded();
                    } else {
                        emmitCallChanged(call, prm);
                    }
                } catch (Exception e) {
                    Log.w(TAG, "Failed to handle call state event", e);
                }
            });

            if (isDisconnected) {
                evict(call);
            }

        } catch (Exception e) {
            Log.w(TAG, "Failed to handle call state event", e);
        }

    }

    void emmitCallChanged(PjSipCall call, OnCallStateParam prm) {
        try {
            final int callId = call.getId();
            Log.d(TAG, "will get info as call was changed");
            final int callState = call.getInfo().getState();
            Log.d(TAG, "got info as call was changed");

            job(new Runnable() {
                @Override
                public void run() {
                    // Acquire wake lock
                    if (mIncallWakeLock == null) {
                        mIncallWakeLock = mPowerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "rnvoip:incall");
                    }
                    if (!mIncallWakeLock.isHeld()) {
                        mIncallWakeLock.acquire();
                    }

                    // Ensure that ringing sound is stopped
                    if (callState != pjsip_inv_state.PJSIP_INV_STATE_INCOMING && !mUseSpeaker && mAudioManager.isSpeakerphoneOn()) {
                        mAudioManager.setSpeakerphoneOn(false);
                    }

                    // Acquire wifi lock
                    mWifiLock.acquire();

                    if (callState == pjsip_inv_state.PJSIP_INV_STATE_EARLY || callState == pjsip_inv_state.PJSIP_INV_STATE_CONFIRMED) {
                        mAudioManager.setMode(AudioManager.MODE_IN_CALL);
                    }
                }
            });
        } catch (Exception e) {
            Log.w(TAG, "Failed to retrieve call state", e);
        }

        mEmitter.fireCallChanged(call);
    }

    void emmitCallTerminated(int callId, String callData, OnCallStateParam prm) {

        job(new Runnable() {
            @Override
            public void run() {
                // Release wake lock
                if (mCalls.size() == 1) {
                    if (mIncallWakeLock != null && mIncallWakeLock.isHeld()) {
                        mIncallWakeLock.release();
                    }
                }

                // Release wifi lock
                if (mCalls.size() == 1) {
                    mWifiLock.release();
                }

                // Reset audio settings
                if (mCalls.size() == 1) {
                    mAudioManager.setSpeakerphoneOn(false);
                    mAudioManager.setMode(AudioManager.MODE_NORMAL);
                }

                mEmitter.fireCallTerminated(callData);
            }
        });
    }

    void emmitCallUpdated(PjSipCall call) {
        mEmitter.fireCallChanged(call);
    }

    /**
     * Pauses active calls once user answer to incoming calls.
     */
    private void doPauseParallelCalls(PjSipCall activeCall) {
        for (PjSipCall call : mCalls) {
            if (activeCall.getId() == call.getId()) {
                continue;
            }

            try {
//                call.hold();
            } catch (Exception e) {
                Log.w(TAG, "Failed to put call on hold", e);
            }
        }
    }

    /**
     * Pauses all calls, used when received GSM call.
     */
    private void doPauseAllCalls() {
        for (PjSipCall call : mCalls) {
            try {
//                call.hold();
            } catch (Exception e) {
                Log.w(TAG, "Failed to put call on hold", e);
            }
        }
    }

    protected class PhoneStateChangedReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            final String extraState = intent.getStringExtra(TelephonyManager.EXTRA_STATE);

//            if (TelephonyManager.EXTRA_STATE_RINGING.equals(extraState) || TelephonyManager.EXTRA_STATE_OFFHOOK.equals(extraState)) {
//                Log.d(TAG, "GSM call received, pause all SIP calls and do not accept incoming SIP calls.");
//
//                mGSMIdle = false;
//
//                job(new Runnable() {
//                    @Override
//                    public void run() {
//                        doPauseAllCalls();
//                    }
//                });
//            } else if (TelephonyManager.EXTRA_STATE_IDLE.equals(extraState)) {
//                Log.d(TAG, "GSM call released, allow to accept incoming calls.");
//                mGSMIdle = true;
//            }
        }
    }

    void setSpeaker(boolean enabled) {
        if (android.os.Build.VERSION.SDK_INT > android.os.Build.VERSION_CODES.P) {
            int device = enabled ? AudioDeviceInfo.TYPE_BUILTIN_SPEAKER : AudioDeviceInfo.TYPE_BUILTIN_EARPIECE;
            PjSipUtils.setCommunicationDevice(mAudioManager, device);
        } else {
            mAudioManager.setSpeakerphoneOn(enabled);
        }
        mUseSpeaker = enabled;
    }
}
