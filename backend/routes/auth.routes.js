const express = require('express');
const router = express.Router();
const authController = require('../controllers/auth.controller');

// Registration Flow
router.post('/send-otp', authController.sendOtp);
router.post('/verify-register', authController.verifyAndRegister);

// Password Reset Flow
router.post('/forgot-password', authController.forgotPassword);
router.post('/reset-password', authController.resetPassword);

module.exports = router;
