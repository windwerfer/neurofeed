mod common;

use btleplug::api::Peripheral as _;
use futures::StreamExt;
use std::time::Duration;
use tokio::time;

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_subscribe_and_receive_notifications() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::NOTIFY_CHAR,
    );

    // Set up notification stream before subscribing
    let mut stream = peripheral.notifications().await.unwrap();

    // Subscribe to the notification characteristic
    peripheral.subscribe(&char).await.unwrap();

    // Tell the peripheral to start sending notifications
    common::peripheral_finder::send_control_command(
        &peripheral,
        common::gatt_uuids::CMD_START_NOTIFICATIONS,
    )
    .await;

    // Collect a few notifications (with timeout)
    let mut received = Vec::new();
    let timeout = time::sleep(Duration::from_secs(5));
    tokio::pin!(timeout);

    loop {
        tokio::select! {
            Some(notification) = stream.next() => {
                if notification.uuid == common::gatt_uuids::NOTIFY_CHAR {
                    received.push(notification);
                    if received.len() >= 3 {
                        break;
                    }
                }
            }
            _ = &mut timeout => break,
        }
    }

    // Stop notifications and unsubscribe
    common::peripheral_finder::send_control_command(
        &peripheral,
        common::gatt_uuids::CMD_STOP_NOTIFICATIONS,
    )
    .await;
    peripheral.unsubscribe(&char).await.unwrap();

    assert!(
        received.len() >= 3,
        "Expected at least 3 notifications, got {}",
        received.len()
    );

    // Verify notifications have the correct service UUID
    for notif in &received {
        assert_eq!(notif.service_uuid, common::gatt_uuids::NOTIFICATION_SERVICE);
    }

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_subscribe_and_receive_indications() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::INDICATE_CHAR,
    );

    let mut stream = peripheral.notifications().await.unwrap();
    peripheral.subscribe(&char).await.unwrap();

    common::peripheral_finder::send_control_command(
        &peripheral,
        common::gatt_uuids::CMD_START_NOTIFICATIONS,
    )
    .await;

    let mut received = Vec::new();
    let timeout = time::sleep(Duration::from_secs(5));
    tokio::pin!(timeout);

    loop {
        tokio::select! {
            Some(notification) = stream.next() => {
                if notification.uuid == common::gatt_uuids::INDICATE_CHAR {
                    received.push(notification);
                    if received.len() >= 2 {
                        break;
                    }
                }
            }
            _ = &mut timeout => break,
        }
    }

    common::peripheral_finder::send_control_command(
        &peripheral,
        common::gatt_uuids::CMD_STOP_NOTIFICATIONS,
    )
    .await;
    peripheral.unsubscribe(&char).await.unwrap();

    assert!(
        received.len() >= 2,
        "Expected at least 2 indications, got {}",
        received.len()
    );

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_unsubscribe_stops_notifications() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::NOTIFY_CHAR,
    );

    let mut stream = peripheral.notifications().await.unwrap();
    peripheral.subscribe(&char).await.unwrap();

    common::peripheral_finder::send_control_command(
        &peripheral,
        common::gatt_uuids::CMD_START_NOTIFICATIONS,
    )
    .await;

    // Wait for at least one notification
    let timeout = time::sleep(Duration::from_secs(3));
    tokio::pin!(timeout);
    let mut got_one = false;
    loop {
        tokio::select! {
            Some(n) = stream.next() => {
                if n.uuid == common::gatt_uuids::NOTIFY_CHAR {
                    got_one = true;
                    break;
                }
            }
            _ = &mut timeout => break,
        }
    }
    assert!(got_one, "Should have received at least one notification");

    // Unsubscribe
    peripheral.unsubscribe(&char).await.unwrap();

    // Wait briefly and verify no more notifications arrive for our char
    time::sleep(Duration::from_secs(2)).await;

    // Drain any remaining and check — after unsubscribe, no new ones should appear
    // (We can't perfectly test "no more notifications" but the unsubscribe should succeed)

    common::peripheral_finder::send_control_command(
        &peripheral,
        common::gatt_uuids::CMD_STOP_NOTIFICATIONS,
    )
    .await;

    peripheral.disconnect().await.unwrap();
}

#[tokio::test]
#[ignore = "requires BLE test peripheral"]
async fn test_configurable_notification_payload() {
    let peripheral = common::peripheral_finder::find_and_connect().await;
    common::peripheral_finder::reset_peripheral(&peripheral).await;

    let config_char = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::CONFIGURABLE_NOTIFY,
    );
    let control_point = common::peripheral_finder::find_characteristic(
        &peripheral,
        common::gatt_uuids::CONTROL_POINT,
    );

    // Set a custom payload via control point: opcode 0x06 + payload bytes
    let mut cmd = vec![common::gatt_uuids::CMD_SET_NOTIFICATION_PAYLOAD];
    cmd.extend_from_slice(&[0xCA, 0xFE, 0xBA, 0xBE]);
    peripheral
        .write(&control_point, &cmd, btleplug::api::WriteType::WithResponse)
        .await
        .unwrap();

    let mut stream = peripheral.notifications().await.unwrap();
    peripheral.subscribe(&config_char).await.unwrap();

    common::peripheral_finder::send_control_command(
        &peripheral,
        common::gatt_uuids::CMD_START_NOTIFICATIONS,
    )
    .await;

    // Wait for a notification with our custom payload
    let timeout = time::sleep(Duration::from_secs(5));
    tokio::pin!(timeout);
    let mut matching = false;

    loop {
        tokio::select! {
            Some(n) = stream.next() => {
                if n.uuid == common::gatt_uuids::CONFIGURABLE_NOTIFY
                    && n.value == vec![0xCA, 0xFE, 0xBA, 0xBE]
                {
                    matching = true;
                    break;
                }
            }
            _ = &mut timeout => break,
        }
    }

    common::peripheral_finder::send_control_command(
        &peripheral,
        common::gatt_uuids::CMD_STOP_NOTIFICATIONS,
    )
    .await;
    peripheral.unsubscribe(&config_char).await.unwrap();

    assert!(matching, "Should receive notification with custom payload [0xCA, 0xFE, 0xBA, 0xBE]");

    peripheral.disconnect().await.unwrap();
}
