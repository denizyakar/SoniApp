const express = require('express');
const router = express.Router();
const User = require('../models/User');

// Update push notification token
router.post('/update-token', async (req, res) => {
    try {
        const { username, token } = req.body;

        if (!username || !token) {
            return res.status(400).json({ message: "Missing Information!" });
        }

        await User.findOneAndUpdate(
            { username: username },
            { deviceToken: token }
        );

        console.log(`✅ Token updated: ${username} -> ${token.substring(0, 5)}...`);
        res.status(200).json({ message: "Token saved" });

    } catch (error) {
        console.error("Token saving error:", error);
        res.status(500).json({ message: "Server error" });
    }
});

// Remove push notification token (logout)
router.post('/remove-token', async (req, res) => {
    try {
        const { username } = req.body;

        if (!username) {
            return res.status(400).json({ message: "Username is missing!" });
        }

        await User.findOneAndUpdate(
            { username: username },
            { deviceToken: "" }
        );

        console.log(`🗑 Token removed! (Logout): ${username}`);
        res.status(200).json({ message: "Token removed" });

    } catch (error) {
        console.error("Token removal error:", error);
        res.status(500).json({ message: "Server error" });
    }
});

// Update VoIP (call) token
router.post("/update-voip-token", async (req, res) => {
    const { username, voipToken } = req.body;

    if (!username || !voipToken) {
        return res.status(400).json({ error: "username and voipToken are required" });
    }

    try {
        const updatedUser = await User.findOneAndUpdate(
            { username },
            { voipToken },
            { new: true }
        );

        if (updatedUser) {
            console.log(`✅ VoIP Token updated: ${username}`);
            res.json({ success: true, message: "VoIP Token saved successfully" });
        } else {
            res.status(404).json({ error: "User not found" });
        }
    } catch (error) {
        console.error("❌ VoIP Token save error:", error);
        res.status(500).json({ error: "Server error" });
    }
});

// Remove VoIP token (logout)
router.post("/remove-voip-token", async (req, res) => {
    const { username } = req.body;

    if (!username) {
        return res.status(400).json({ error: "username is required" });
    }

    try {
        await User.findOneAndUpdate(
            { username },
            { voipToken: "" }
        );

        console.log(`✅ VoIP Token removed: ${username}`);
        res.json({ success: true, message: "VoIP Token removed successfully" });
    } catch (error) {
        console.error("❌ VoIP Token removal error:", error);
        res.status(500).json({ error: "Server error" });
    }
});

module.exports = router;
