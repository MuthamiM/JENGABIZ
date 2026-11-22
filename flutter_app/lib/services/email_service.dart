import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../config/secrets.dart';

class EmailVerificationResult {
  final bool success;
  final String code;
  final String? message;
  final bool isSandboxFallback;

  EmailVerificationResult({
    required this.success,
    required this.code,
    this.message,
    this.isSandboxFallback = false,
  });
}

class EmailService {
  static const String _resendApiKey = AppSecrets.resendApiKey;
  static const String _resendEndpoint = 'https://api.resend.com/emails';
  static const String _fromEmail = AppSecrets.resendFromEmail;

  static String generateCode() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  /// Sends a verification email to the user with the specified OTP code.
  static Future<EmailVerificationResult> sendVerificationEmail({
    required String recipientEmail,
    required String shopName,
    required String code,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.parse(_resendEndpoint);
      final request = await client.postUrl(uri);

      request.headers.set('Authorization', 'Bearer $_resendApiKey');
      request.headers.set('Content-Type', 'application/json');

      final emailBody = {
        'from': 'JengaBiz <$_fromEmail>',
        'to': [recipientEmail],
        'subject': 'Your JengaBiz Verification Code: $code',
        'html': '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>JengaBiz Verification</title>
</head>
<body style="font-family: Arial, sans-serif; background-color: #f8f8ff; margin: 0; padding: 24px;">
  <div style="max-width: 520px; margin: 0 auto; background: #ffffff; border-radius: 16px; padding: 32px; border: 1px solid #e2e8f0;">
    <div style="text-align: center; margin-bottom: 24px;">
      <h1 style="color: #1e6bff; font-size: 26px; margin: 0; font-weight: 800;">JengaBiz</h1>
      <p style="color: #64748b; font-size: 14px; margin-top: 4px;">Smart Shop Inventory & Ledger Management</p>
    </div>
    <div style="border-top: 1px solid #f1f5f9; padding-top: 20px;">
      <h2 style="color: #1e293b; font-size: 18px; margin: 0 0 12px 0;">Verify your shop account</h2>
      <p style="color: #475569; font-size: 14px; line-height: 1.6; margin: 0 0 20px 0;">
        Welcome to JengaBiz, <strong>$shopName</strong>! Use the verification code below to activate your account and access your shop inventory ledger:
      </p>
      <div style="background-color: #f0f4ff; border-radius: 12px; padding: 18px; text-align: center; margin-bottom: 24px; border: 1px dashed #1e6bff;">
        <span style="font-size: 32px; font-weight: 800; letter-spacing: 6px; color: #1e6bff;">$code</span>
      </div>
      <p style="color: #94a3b8; font-size: 12px; line-height: 1.5; margin: 0;">
        This code expires in 15 minutes. If you did not create a JengaBiz account, you can safely ignore this email.
      </p>
    </div>
  </div>
</body>
</html>
''',
        'text': 'Welcome to JengaBiz, $shopName! Your verification code is: $code. Enter this in the app to activate your account.',
      };

      request.write(jsonEncode(emailBody));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EmailVerificationResult(
          success: true,
          code: code,
          message: 'Verification code sent to $recipientEmail',
        );
      } else {
        try {
          final data = jsonDecode(responseBody) as Map<String, dynamic>;
          final msg = data['message'] as String? ?? 'Resend service rejected the recipient email.';
          return EmailVerificationResult(
            success: false,
            code: code,
            message: msg,
          );
        } catch (_) {
          return EmailVerificationResult(
            success: false,
            code: code,
            message: 'Email service error (${response.statusCode}). Please verify your email.',
          );
        }
      }
    } catch (e) {
      return EmailVerificationResult(
        success: false,
        code: code,
        message: 'Could not reach mail service. Check your connection.',
      );
    } finally {
      client.close();
    }
  }
}
