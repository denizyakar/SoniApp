const express = require('express');
const router = express.Router();
const Message = require('../models/Message');
const { chatUpload } = require('../config/upload');

// Fetch old messages between two users
router.get('/', async (req, res) => {
    try {
        const { from, to } = req.query;

        const messages = await Message.find({
            $or: [
                { senderId: from, receiverId: to },
                { senderId: to, receiverId: from },
            ],
        })
            .sort({ date: 1 })
            .lean();

        const formatted = messages.map(msg => ({
            _id: msg._id.toString(),
            text: msg.text,
            senderId: msg.senderId.toString(),
            receiverId: msg.receiverId.toString(),
            date: msg.date ? msg.date.toISOString() : null,
            senderName: msg.senderName || '',
            isRead: msg.isRead || false,
            readAt: msg.readAt ? msg.readAt.toISOString() : null,
            imageUrl: msg.imageUrl || null,
        }));

        res.json(formatted);
    } catch (err) {
        console.error('GET /messages error:', err);
        res.status(500).json({ error: 'Server error' });
    }
});

// Upload chat image
router.post('/upload', chatUpload.single('image'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
    }
    const imageUrl = `/uploads/messages/${req.file.filename}`;
    res.json({ imageUrl });
});

module.exports = router;
