mod common;

use btleplug::api::{Central, CentralEvent, Peripheral as _, ScanFilter};
use futures::StreamExt;
use std::time::Duration;
use tokio::time;

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_discover_peripheral_by_name() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    let props = peripheral.properties().await.unwrap().unwrap();
    let name = props.local_name.unwrap_or_default();
    let expected = std::env::var("BTLEPLUG_TEST_PERIPHERAL")
        .unwrap_or_else(|_| common::gatt_uuids::TEST_PERIPHERAL_NAME.to_string());
    assert_eq!(name, expected);
    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_discover_services() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    let services = peripheral.services();

    // Should have at least our 4 test services
    let service_uuids: Vec<_> = services.iter().map(|s| s.uuid).collect();
    assert!(
        service_uuids.contains(&common::gatt_uuids::CONTROL_SERVICE),
        "Control Service not found in {:?}",
        service_uuids
    );
    assert!(
        service_uuids.contains(&common::gatt_uuids::READ_WRITE_SERVICE),
        "Read/Write Service not found"
    );
    assert!(
        service_uuids.contains(&common::gatt_uuids::NOTIFICATION_SERVICE),
        "Notification Service not found"
    );
    assert!(
        service_uuids.contains(&common::gatt_uuids::DESCRIPTOR_SERVICE),
        "Descriptor Service not found"
    );

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_discover_characteristics() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    let chars = peripheral.characteristics();
    let char_uuids: Vec<_> = chars.iter().map(|c| c.uuid).collect();

    // Spot-check key characteristics exist
    assert!(char_uuids.contains(&common::gatt_uuids::CONTROL_POINT));
    assert!(char_uuids.contains(&common::gatt_uuids::STATIC_READ));
    assert!(char_uuids.contains(&common::gatt_uuids::NOTIFY_CHAR));
    assert!(char_uuids.contains(&common::gatt_uuids::DESCRIPTOR_TEST_CHAR));

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_scan_filter_by_service_uuid() {
    let adapter = common::peripheral_finder::get_adapter().await;

    // Scan with filter for our Control Service UUID
    adapter
        .start_scan(ScanFilter {
            services: vec![common::gatt_uuids::CONTROL_SERVICE],
        })
        .await
        .unwrap();

    time::sleep(Duration::from_secs(5)).await;

    let peripherals = adapter.peripherals().await.unwrap();
    adapter.stop_scan().await.unwrap();

    // At least one peripheral should match (our test peripheral)
    assert!(
        !peripherals.is_empty(),
        "No peripherals found with Control Service UUID filter"
    );
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_advertisement_manufacturer_data() {
    let adapter = common::peripheral_finder::get_adapter().await;
    let mut events = adapter.events().await.unwrap();

    adapter
        .start_scan(ScanFilter::default())
        .await
        .unwrap();

    let mut found_manufacturer_data = false;
    let timeout = time::sleep(Duration::from_secs(10));
    tokio::pin!(timeout);

    loop {
        tokio::select! {
            Some(event) = events.next() => {
                if let CentralEvent::ManufacturerDataAdvertisement { manufacturer_data, .. } = event {
                    if manufacturer_data.contains_key(&common::gatt_uuids::MANUFACTURER_COMPANY_ID) {
                        found_manufacturer_data = true;
                        break;
                    }
                }
            }
            _ = &mut timeout => break,
        }
    }

    adapter.stop_scan().await.unwrap();
    assert!(
        found_manufacturer_data,
        "Did not receive ManufacturerDataAdvertisement with company ID 0xFFFF"
    );
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_advertisement_services() {
    let adapter = common::peripheral_finder::get_adapter().await;
    let mut events = adapter.events().await.unwrap();

    adapter
        .start_scan(ScanFilter::default())
        .await
        .unwrap();

    let mut found_services = false;
    let timeout = time::sleep(Duration::from_secs(10));
    tokio::pin!(timeout);

    loop {
        tokio::select! {
            Some(event) = events.next() => {
                if let CentralEvent::ServicesAdvertisement { services, .. } = event {
                    if services.contains(&common::gatt_uuids::CONTROL_SERVICE) {
                        found_services = true;
                        break;
                    }
                }
            }
            _ = &mut timeout => break,
        }
    }

    adapter.stop_scan().await.unwrap();
    assert!(
        found_services,
        "Did not receive ServicesAdvertisement with Control Service UUID"
    );
}
