package com.carusto.ReactNativePjSip;

import android.content.Context;
import android.util.Log;
import org.pjsip.pjsua2.LogEntry;
import org.pjsip.pjsua2.LogWriter;
import org.pjsip.pjsua2.pjsua2JNI;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;

public class PjSipLogWriter extends LogWriter {

    private static String TAG = "PjSipLogWriter";

    private final File logFile;

    private BufferedWriter bufferedWriter;

    public PjSipLogWriter(Context context) {
        String path = PjSipUtils.getLogsFilePath(context);
        logFile = new File(path);

        Log.d(TAG, "Init log writer for a file at" + path);

        if (!logFile.exists()) {
            try {
                if (!logFile.createNewFile()) {
                    Log.e(TAG, "Failed to create log file");
                    return;
                } else {
                    Log.d(TAG, "Created log file");
                }
            } catch (IOException e) {
                Log.e(TAG, "Error creating log file", e);
            }
        } else {
            Log.d(TAG, "File exists");
        }

        try {
            FileWriter fileWriter = new FileWriter(logFile, true);
            bufferedWriter = new BufferedWriter(fileWriter);
        } catch (IOException e) {
            Log.e(TAG, "Error setting up file logger", e);
        }
    }

    public void write(LogEntry entry) {
        Log.d(TAG, entry.getMsg());

        try {
            bufferedWriter.write(entry.getMsg() + "\n");
        } catch (IOException e) {
            Log.e(TAG, "Error writing to log file", e);
        }
    }

    public synchronized void flush() {
        try {
            bufferedWriter.flush();
        } catch (IOException e) {
            Log.e(TAG, "Error flushing log file", e);
        }
    }

    public synchronized void close() {
        try {
            bufferedWriter.close();
        } catch (IOException e) {
            Log.e(TAG, "Error closing log file", e);
        }
    }

    @Override
    protected void finalize() {
        super.finalize();
        close();
    }

}
