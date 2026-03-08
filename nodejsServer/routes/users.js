const express = require('express');
const router = express.Router();
const User = require('../models/User');
const Message = require('../models/Message');
const { authenticateToken } = require('../middleware/auth');
const { avatarUpload } = require('../config/upload');

// Get all users with unread counts
router.get('/', authenticateToken, async (req, res) => {
    try {
        const users = await User.find().select('-password');
        const myId = req.user.userId || req.user.id || req.user._id;

        const usersWithUnread = await Promise.all(users.map(async (user) => {
            let unreadCount = 0;

            if (user._id.toString() !== myId) {
                unreadCount = await Message.countDocuments({
                    senderId: user._id,
                    receiverId: myId,
                    isRead: false
                });
            }

            return {
                ...user.toObject(),
                unreadCount: unreadCount
            };
        }));

        res.json(usersWithUnread);
    } catch (error) {
        console.error("Fetch users error:", error);
        res.status(500).json({ message: "Couldn't fetch users with counts." });
    }
});

// Get user profile
router.get('/:userId/profile', async (req, res) => {
    try {
        const user = await User.findById(req.params.userId);
        if (!user) return res.status(404).json({ message: 'User not found' });
        res.json({ user });
    } catch (err) {
        res.status(500).json({ message: 'Server error' });
    }
});

// Update user profile (with avatar support)
router.put('/:userId/profile', avatarUpload.single('avatarFile'), async (req, res) => {
    try {
        const { nickname, avatarName } = req.body;
        let updateData = { nickname, avatarName };

        if (req.file) {
            updateData.avatarUrl = `/uploads/avatars/${req.file.filename}?v=${Date.now()}`;
        }
        else if ('avatarUrl' in req.body) {
            updateData.avatarUrl = req.body.avatarUrl;
        }

        const user = await User.findByIdAndUpdate(
            req.params.userId,
            updateData,
            { new: true }
        );

        if (!user) return res.status(404).json({ message: 'User not found' });
        res.json({ message: 'Profile updated', user });

    } catch (err) {
        console.error(err);
        res.status(500).json({ message: 'Server error' });
    }
});

module.exports = router;
