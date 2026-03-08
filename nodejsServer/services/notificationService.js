const apn = require('apn');
const path = require('path');

// APN Provider Settings 
const apnProvider = new apn.Provider({
    token: {
        key: path.join(__dirname, 'AuthKey.p8'), // Check file name
        keyId: 'YOUR_KEY_ID', // Key ID
        teamId: 'YOUR_TEAM_ID', // Team ID
    },
    production: true
});


//PUSH NOTIFICATION
const sendPushNotification = (deviceToken, title, body, senderId) => {

    let notification = new apn.Notification();

    // Bundle ID
    notification.topic = "YOUR_BUNDLE_ID";

    notification.expiry = Math.floor(Date.now() / 1000) + 3600; // valid for 1 hour
    notification.badge = 1;
    notification.sound = "ping.aiff";

    notification.alert = {
        title: title,
        body: body
    };

    // payload
    notification.payload = {
        senderIdFromPayload: senderId
    };

    // sending process
    apnProvider.send(notification, deviceToken).then((result) => {
        if (result.failed.length > 0) {
            console.log("❌ Normal Notification error:", result.failed);
        } else {
            console.log("✅ Normal Notification successful!");
        }
    });
};

// VOIP - CALLKIT
const sendVoipPushNotification = (voipDeviceToken, callerId, callerName, callerAvatarUrl) => {

    let voipNotification = new apn.Notification();

    voipNotification.topic = "YOUR_BUNDLE_ID.voip";
    voipNotification.pushType = "voip";

    voipNotification.priority = 10;

    voipNotification.payload = {
        type: "incomingCall",
        callerId: callerId,
        callerName: callerName,
        callerAvatarUrl: callerAvatarUrl || "",
        callUUID: require('crypto').randomUUID()
    };

    console.log(`[VoIP] Sending push to token: ${voipDeviceToken.substring(0, 10)}...`);

    // Send notification
    apnProvider.send(voipNotification, voipDeviceToken).then((result) => {
        if (result.failed.length > 0) {
            console.log("❌ VoIP Notification error:", JSON.stringify(result.failed, null, 2));
        } else {
            console.log("✅ VoIP Notification sent successfully");
        }
    });
};


module.exports = {
    sendPushNotification,
    sendVoipPushNotification
};

