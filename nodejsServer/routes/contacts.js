const express = require('express');
const router = express.Router();
const User = require('../models/User');
const Message = require('../models/Message');
const { authenticateToken } = require('../middleware/auth');

// Get my contacts (with unread counts)
router.get('/', authenticateToken, async (req, res) => {
    try {
        const myId = req.user.userId || req.user.id;
        const user = await User.findById(myId).populate('contacts', '-password');
        const contactsWithUnread = await Promise.all(user.contacts.map(async (contact) => {
            const unreadCount = await Message.countDocuments({ senderId: contact._id, receiverId: myId, isRead: false });
            return { ...contact.toObject(), unreadCount };
        }));
        res.json(contactsWithUnread);
    } catch (error) {
        console.error("Fetch contacts error:", error);
        res.status(500).json({ message: "Couldn't fetch contacts." });
    }
});

// Add a contact
router.post('/add', authenticateToken, async (req, res) => {
    try {
        const myId = req.user.userId || req.user.id;
        const { contactId } = req.body;
        await User.findByIdAndUpdate(myId, { $addToSet: { contacts: contactId } });
        const contact = await User.findById(contactId).select('-password');
        const unreadCount = await Message.countDocuments({ senderId: contactId, receiverId: myId, isRead: false });
        res.json({ ...contact.toObject(), unreadCount });
    } catch (error) {
        console.error("Add contact error:", error);
        res.status(500).json({ message: "Couldn't add contact." });
    }
});

// Remove a contact
router.delete('/remove', authenticateToken, async (req, res) => {
    try {
        const myId = req.user.userId || req.user.id;
        const { contactId } = req.body;
        await User.findByIdAndUpdate(myId, { $pull: { contacts: contactId } });
        res.json({ success: true });
    } catch (error) {
        console.error("Remove contact error:", error);
        res.status(500).json({ message: "Couldn't remove contact." });
    }
});

module.exports = router;
