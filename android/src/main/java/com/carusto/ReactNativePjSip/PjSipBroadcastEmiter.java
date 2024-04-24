package com.carusto.ReactNativePjSip;

import static org.pjsip.pjsua2.pj_constants_.PJ_SUCCESS;
import static org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_OK;

import android.content.Context;
import android.content.Intent;
import android.util.Log;
import org.json.JSONArray;
import org.json.JSONObject;
import org.pjsip.pjsua2.Account;
import org.pjsip.pjsua2.OnRegStateParam;

import java.util.List;

public class PjSipBroadcastEmiter {

    private static String TAG = "PjSipBroadcastEmiter";

    private Context context;

    public PjSipBroadcastEmiter(Context context) {
        this.context = context;
    }

    public void fireStarted(Intent original, List<PjSipAccount> accounts, List<PjSipCall> calls, JSONObject settings) {
        try {
            JSONArray dataAccounts = new JSONArray();
            for (PjSipAccount account : accounts) {
                dataAccounts.put(account.toJson());
            }

            JSONArray dataCalls = new JSONArray();
            for (PjSipCall call : calls) {
                dataCalls.put(call.toJson());
            }

            JSONObject data = new JSONObject();
            data.put("accounts", dataAccounts);
            data.put("calls", dataCalls);

            if (settings != null) {
                data.put("settings", settings);
            }

            if (accounts.size() > 0) {
                PjSipAccount account = accounts.get(0);
                OnRegStateParam regParam = account.getLastRegStateParam();
                if (regParam != null) {
                    JSONObject regInfo = PjSipUtils.mapRegStateToRegInfo(regParam);
                    if (regInfo != null) {
                        data.put("regInfo", regInfo);
                    }
                }
            }

            Intent intent = new Intent();
            intent.setAction(PjActions.EVENT_STARTED);
            intent.putExtra("callback_id", original.getIntExtra("callback_id", -1));
            intent.putExtra("data", data.toString());

            context.sendBroadcast(intent);
        } catch (Exception e) {
            Log.e(TAG, "Failed to send ACCOUNT_CREATED event", e);
        }
    }

    public void fireIntentHandled(Intent original, JSONObject result) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_HANDLED);
        intent.putExtra("callback_id", original.getIntExtra("callback_id", -1));
        intent.putExtra("data", result.toString());

        context.sendBroadcast(intent);
    }

    public void fireIntentHandled(Intent original) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_HANDLED);
        intent.putExtra("callback_id", original.getIntExtra("callback_id", -1));

        context.sendBroadcast(intent);
    }

    public void fireIntentHandled(Intent original, Exception e) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_HANDLED);
        intent.putExtra("callback_id", original.getIntExtra("callback_id", -1));
        intent.putExtra("exception", e.getMessage());

        context.sendBroadcast(intent);
    }

    public void fireAccountCreated(Intent original, PjSipAccount account) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_ACCOUNT_CREATED);
        intent.putExtra("callback_id", original.getIntExtra("callback_id", -1));
        intent.putExtra("data", account.toJsonString());

        context.sendBroadcast(intent);
    }

    public void fireRegistrationChangeEvent(PjSipAccount account, OnRegStateParam prm) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_REGISTRATION_CHANGED);
        try {
            JSONObject regInfo = PjSipUtils.mapRegStateToRegInfo(prm);
            JSONObject dataObject = new JSONObject();

            dataObject.put("account", account.toJson());
            dataObject.put("regInfo", regInfo);

            intent.putExtra("data", dataObject.toString());

            context.sendBroadcast(intent);
        } catch (Exception e) {
           e.printStackTrace();
        }
    }

    public void fireLaunchStatusUpdateEvent(Boolean isLaunched) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_LAUNCH_STATUS_UPDATED);

        try {
            JSONObject dataObject = new JSONObject();
            dataObject.put("isLaunched", isLaunched);
            intent.putExtra("data", dataObject.toString());

            context.sendBroadcast(intent);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public void fireMessageReceivedEvent(PjSipMessage message) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_MESSAGE_RECEIVED);
        intent.putExtra("data", message.toJsonString());

        context.sendBroadcast(intent);
    }

    public void fireCallReceivedEvent(PjSipCall call) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_CALL_RECEIVED);
        intent.putExtra("data", call.toJsonString());

        context.sendBroadcast(intent);
    }

    public void fireCallChanged(PjSipCall call) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_CALL_CHANGED);
        intent.putExtra("data", call.toJsonString());

        context.sendBroadcast(intent);
    }

    public void fireCallTerminated(PjSipCall call) {
        Intent intent = new Intent();
        intent.setAction(PjActions.EVENT_CALL_TERMINATED);
        intent.putExtra("data", call.toJsonString());

        context.sendBroadcast(intent);
    }
}
