mod common;

use btleplug::api::{Peripheral as _, ConnectionParameterPreset};

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_mtu_after_connection() {
    let peripheral = common::peripheral_finder::find_and_connect().await;

    let mtu = peripheral.mtu();
    // After connection, MTU should be at least the default BLE MTU (23)
    // and potentially higher if MTU exchange succeeded
    assert!(
        mtu >= 23,
        "MTU should be at least 23 (default), got {}",
        mtu
    );

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_read_rssi() {
    let peripheral = common::peripheral_finder::find_and_connect().await;

    match peripheral.read_rssi().await {
        Ok(rssi) => {
            // RSSI should be a negative dBm value (typically -30 to -100)
            assert!(
                rssi < 0 && rssi > -120,
                "RSSI should be between -120 and 0 dBm, got {}",
                rssi
            );
        }
        Err(btleplug::Error::NotSupported(_)) => {
            // Some platforms may not support read_rssi — acceptable
        }
        Err(e) => {
            panic!("Unexpected error from read_rssi: {:?}", e);
        }
    }

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_properties_contain_peripheral_info() {
    let peripheral = common::peripheral_finder::find_and_connect().await;

    let props = peripheral
        .properties()
        .await
        .unwrap()
        .expect("properties should be available");

    // Should have a local name
    let expected_name = std::env::var("BTLEPLUG_TEST_PERIPHERAL")
        .unwrap_or_else(|_| common::gatt_uuids::TEST_PERIPHERAL_NAME.to_string());
    assert_eq!(
        props.local_name.as_deref(),
        Some(expected_name.as_str()),
    );

    // Should have manufacturer data
    assert!(
        props
            .manufacturer_data
            .contains_key(&common::gatt_uuids::MANUFACTURER_COMPANY_ID),
        "Properties should contain manufacturer data with company ID 0xFFFF"
    );

    // RSSI should be present from scan
    assert!(props.rssi.is_some(), "RSSI from scan should be present");

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_connection_parameters() {
    let peripheral = common::peripheral_finder::find_and_connect().await;

    match peripheral.connection_parameters().await {
        Ok(Some(params)) => {
            // Connection interval should be reasonable (7.5ms to 4000ms)
            assert!(
                params.interval_us >= 7_500 && params.interval_us <= 4_000_000,
                "Connection interval out of range: {} us",
                params.interval_us
            );
            // Latency should be 0-499
            assert!(
                params.latency <= 499,
                "Latency out of range: {}",
                params.latency
            );
            // Supervision timeout should be 100ms to 32s
            assert!(
                params.supervision_timeout_us >= 100_000
                    && params.supervision_timeout_us <= 32_000_000,
                "Supervision timeout out of range: {} us",
                params.supervision_timeout_us
            );
        }
        Ok(None) => {
            // Platform doesn't support reading connection parameters
        }
        Err(btleplug::Error::NotSupported(_)) => {
            // Platform doesn't implement this
        }
        Err(e) => {
            panic!("Unexpected error from connection_parameters: {:?}", e);
        }
    }

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_request_connection_parameters() {
    let peripheral = common::peripheral_finder::find_and_connect().await;

    // Request throughput-optimized parameters
    match peripheral
        .request_connection_parameters(ConnectionParameterPreset::ThroughputOptimized)
        .await
    {
        Ok(()) => {
            // Brief pause for the parameter update to take effect
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;

            // Verify parameters changed (if platform supports reading them)
            if let Ok(Some(params)) = peripheral.connection_parameters().await {
                // ThroughputOptimized should have a lower interval
                // (exact values depend on platform and negotiation)
                assert!(
                    params.interval_us > 0,
                    "Connection interval should be positive after update"
                );
            }
        }
        Err(btleplug::Error::NotSupported(_)) => {
            // Platform doesn't support requesting parameter updates
        }
        Err(e) => {
            panic!(
                "Unexpected error from request_connection_parameters: {:?}",
                e
            );
        }
    }

    peripheral.disconnect().await.unwrap();
}
