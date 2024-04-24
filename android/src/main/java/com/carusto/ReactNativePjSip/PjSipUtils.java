package com.carusto.ReactNativePjSip;

import static org.pjsip.pjsua2.pj_constants_.PJ_SUCCESS;
import org.json.JSONObject;
import org.pjsip.pjsua2.OnRegStateParam;
import org.pjsip.pjsua2.SipHeader;
import org.pjsip.pjsua2.SipHeaderVector;

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
            regInfo.put("success", prm.getStatus() == PJ_SUCCESS.swigValue());
            regInfo.put("code", prm.getStatus());
            regInfo.put("reason", prm.getReason());
            return regInfo;
        } catch (Exception e) {
            return  null;
        }
    }
}
