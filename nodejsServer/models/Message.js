const mongoose = require('mongoose');

const MessageSchema = new mongoose.Schema({
  text: { type: String, required: false },
  senderId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  receiverId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  date: { type: Date, default: Date.now },
  senderName: { type: String, default: '' },
  isRead: { type: Boolean, default: false },
  readAt: { type: Date, default: null },
  clientId: { type: String, default: null },
  imageUrl: String,

});

module.exports = mongoose.model('Message', MessageSchema);
