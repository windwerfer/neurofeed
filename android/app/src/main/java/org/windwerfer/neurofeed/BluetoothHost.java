package org.windwerfer.neurofeed;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.content.Context;

public final class BluetoothHost {
    private static volatile Context appContext;

    private BluetoothHost() {}

    public static void setAppContext(Context context) {
        if (context == null) return;
        appContext = context.getApplicationContext();
    }

    public static BluetoothAdapter adapter() {
        Context ctx = appContext;
        if (ctx != null) {
            Object service = ctx.getSystemService(Context.BLUETOOTH_SERVICE);
            if (service instanceof BluetoothManager) {
                BluetoothAdapter adapter = ((BluetoothManager) service).getAdapter();
                if (adapter != null) return adapter;
            }
        }
        return BluetoothAdapter.getDefaultAdapter();
    }
}
