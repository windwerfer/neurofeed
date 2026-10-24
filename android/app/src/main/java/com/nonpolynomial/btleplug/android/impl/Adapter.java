package com.nonpolynomial.btleplug.android.impl;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter.Builder;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.os.Build;
import android.os.ParcelUuid;

import org.windwerfer.neurofeed.BluetoothHost;

import java.util.ArrayList;
import java.util.List;

@SuppressWarnings("unused") // Native code uses this class.
class Adapter {
    private long handle;
    private final Callback callback = new Callback();

    public Adapter() {}

    @SuppressLint("MissingPermission")
    public void startScan(ScanFilter filter) {
        BluetoothAdapter bluetoothAdapter = BluetoothHost.adapter();
        if (bluetoothAdapter == null) {
          throw new NoBluetoothAdapterException();
        }
        if (!bluetoothAdapter.isEnabled()) {
          throw new RuntimeException("Bluetooth is turned off");
        }

        ArrayList<android.bluetooth.le.ScanFilter> filters = null;
        String[] uuids = filter.getUuids();
        if (uuids.length > 0) {
            filters = new ArrayList<>();
            for (String uuid : uuids) {
                filters.add(new Builder().setServiceUuid(ParcelUuid.fromString(uuid)).build());
            }
        }
        ScanSettings.Builder settingsBuilder = new ScanSettings.Builder()
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES);
        if (Build.VERSION.SDK_INT >= 26 &&
                bluetoothAdapter.isLeExtendedAdvertisingSupported()) {
            settingsBuilder.setLegacy(false);
        }
        ScanSettings settings = settingsBuilder.build();
        BluetoothLeScanner scanner = bluetoothAdapter.getBluetoothLeScanner();
        if (scanner == null) {
          throw new RuntimeException("Bluetooth is turned off");
        }
        scanner.startScan(filters, settings, this.callback);
    }

    @SuppressLint("MissingPermission")
    public void stopScan() {
        BluetoothAdapter bluetoothAdapter = BluetoothHost.adapter();
        if (bluetoothAdapter != null) {
            BluetoothLeScanner scanner = bluetoothAdapter.getBluetoothLeScanner();
            if (scanner != null) {
                scanner.stopScan(this.callback);
            }
        }
    }

    private native void reportScanResult(ScanResult result);

    public native void onConnectionStateChanged(String address, boolean connected);

    private class Callback extends ScanCallback {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            Adapter.this.reportScanResult(result);
        }
    }
}
