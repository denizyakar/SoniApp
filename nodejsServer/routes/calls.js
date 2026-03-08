const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../middleware/auth');

// Check for pending call offers (when woken by VoIP push)
router.get('/api/calls/pending/:userId', (req, res) => {
    const userId = req.params.userId;

    const authHeader = req.headers['authorization'];
    if (!authHeader) {
        return res.status(401).json({ success: false, message: "No token provided" });
    }
    const token = authHeader.split(' ')[1];

    try {
        const decoded = jwt.verify(token, JWT_SECRET);

        // Get pendingOffers from app-level shared state
        const pendingOffers = req.app.get('pendingOffers');

        console.log(`📞 Pending call check for User: ${userId}`);
        if (pendingOffers.has(userId)) {
            const callData = pendingOffers.get(userId);
            res.status(200).json({ success: true, data: callData });
            pendingOffers.delete(userId);
            console.log(`✅ Pending call delivered to User: ${userId}`);
        } else {
            res.status(404).json({ success: false, message: "No pending calls" });
        }
    } catch (err) {
        return res.status(401).json({ success: false, message: "Invalid or expired token" });
    }
});

module.exports = router;
