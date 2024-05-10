package com.carusto.ReactNativePjSip;

import static android.content.Context.AUDIO_SERVICE;
import static org.pjsip.pjsua2.pj_constants_.PJ_SUCCESS;

import android.content.Context;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.os.Build;
import android.util.Log;

import androidx.annotation.RequiresApi;

import org.json.JSONObject;
import org.pjsip.pjsua2.OnRegStateParam;
import org.pjsip.pjsua2.SipHeader;
import org.pjsip.pjsua2.SipHeaderVector;

import java.io.File;
import java.util.List;
import java.util.Map;

public class PjSipUtils {

    public static SipHeaderVector mapToSipHeaderVector(Map<String, String> headers) {
        SipHeaderVector hdrsVector = new SipHeaderVector();

        for (Map.Entry<String, String> entry : headers.entrySet()) {
            SipHeader hdr = new SipHeader();
            hdr.setHName(entry.getKey());
            hdr.setHValue(entry.getValue());

            hdrsVector.add(hdr);
        }

        return hdrsVector;
    }

    public static JSONObject mapRegStateToRegInfo(OnRegStateParam prm) {
        try {
            JSONObject regInfo = new JSONObject();
            regInfo.put("success", prm.getStatus() == PJ_SUCCESS);
            regInfo.put("code", prm.getCode());
            regInfo.put("reason", prm.getReason());
            return regInfo;
        } catch (Exception e) {
            return  null;
        }
    }

    public static String getLogsFilePath(Context context) {
        String filename = "pjsip_log.log";
        File logFile = new File(context.getFilesDir(), filename);
        return logFile.getAbsolutePath();
    }

    @RequiresApi(api = Build.VERSION_CODES.S)
    public static boolean setCommunicationDevice(AudioManager audioManager, Integer targetDeviceType) {
        List<AudioDeviceInfo> devices = audioManager.getAvailableCommunicationDevices();
        for (AudioDeviceInfo device: devices) {
            if (device.getType() == targetDeviceType) {
                boolean result = audioManager.setCommunicationDevice(device);
                return result;
            }
        }
        return false;
    }

}
