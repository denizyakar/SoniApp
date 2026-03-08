const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
  username: {
    type: String,
    required: true,
    unique: true
  },
  password: {
    type: String,
    required: true
  },
  nickname: { type: String, default: '' },
  avatarName: { type: String, default: 'person.circle' },
  avatarUrl: { type: String, default: '' },
  deviceToken: { type: String, default: "" },
  voipToken: { type: String, default: "" },
  contacts: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }]

});

module.exports = mongoose.model('User', UserSchema);

