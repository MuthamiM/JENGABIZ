import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../legal_documents.dart';
import '../services/db_service.dart';
import '../services/api_service.dart';
import '../services/firebase_push_service.dart';
import '../services/location_biometric_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onSuccess, required this.onBack});
  final VoidCallback onSuccess;
  final VoidCallback onBack;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isSignUp = true;
  bool isVerifyingCode = false;
  bool _needsAccountMigration = false;
  bool _acceptedTerms = false;
  bool _isPasswordReset = false;
  bool _resetOtpVerified = false;
  String? _resetVerificationToken;

  final _nameCtrl = TextEditingController();
  final _shopCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _referralCodeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _loading = false;
  bool _canUseBiometrics = false;
  bool _accountSuspended = false;
  bool _supportRequestSending = false;
  String? _supportTicketId;
  String? _detectedReferralCounty;
  String? _error;
  String _supportName = 'MF Technologies';
  String _supportAdminName = 'MF Technologies Admin';
  String _supportEmail = 'info@mftechnologies.org';
  List<String> _supportPhoneNumbers = const ['0748329410', '0712742991'];

  @override
  void initState() {
    super.initState();
    if (JengaDB.instance.users.isNotEmpty) {
      isSignUp = false;
      final lastUser = JengaDB.instance.users.first;
      _emailCtrl.text = lastUser.email;
      _phoneCtrl.text = lastUser.phone;
    }
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final available =
        await LocationBiometricService.instance.canUseBiometrics();
    if (mounted) setState(() => _canUseBiometrics = available);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shopCtrl.dispose();
    _phoneCtrl.dispose();
    _referralCodeCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
      _accountSuspended = false;
      _supportTicketId = null;
    });

    try {
      if (_isPasswordReset) {
        final email = _emailCtrl.text.trim();
        if (email.isEmpty || !email.contains('@')) {
          throw const FormatException('Enter your account email address.');
        }
        if (_resetOtpVerified) {
          await _completePasswordReset();
        } else {
          await _requestEmailCode(email);
        }
        return;
      }

      if (isSignUp && !_acceptedTerms) {
        throw const FormatException(
          'Agree to the Terms of Use and Privacy Policy to create an account.',
        );
      }
      if (isSignUp &&
          (_nameCtrl.text.trim().isEmpty || _shopCtrl.text.trim().isEmpty)) {
        throw const FormatException(
            'Enter your name and shop name to continue.');
      }
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      if (email.isEmpty || !email.contains('@')) {
        throw const FormatException('Enter a valid email address.');
      }
      if (isSignUp && JengaDB.instance.findUser(email) != null) {
        throw const FormatException(
          'This email already has an account on this device. Choose Sign In or use a different email.',
        );
      }
      if (password.length < 8) {
        throw const FormatException(
            'Use a password with at least 8 characters.');
      }

      if (!isSignUp) {
        final user = JengaDB.instance.findUser(email);
        final api = JengaApiService.instance;
        if (api.authToken != null && api.sessionEmail != email.toLowerCase()) {
          await api.clearSession();
        }
        final response = await api.loginAccount(email, password);
        if (response?.succeeded == true) {
          final stockSynced =
              await _activateRemoteAccount(response!.data, password);
          if (!stockSynced && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Signed in. Stock sync will retry when the connection returns.'),
              ),
            );
          }
          if (mounted) widget.onSuccess();
          return;
        }
        if (response?.data['code'] == 'ACCOUNT_SUSPENDED') {
          _applySuspensionSupport(response?.data['support']);
          throw const FormatException(
            'This account is suspended. Contact MF Technologies to request a review.',
          );
        }

        final localPasswordValid = user?.passwordHash == null
            ? user != null
            : await JengaDB.instance.verifyLocalPassword(email, password);
        if (localPasswordValid && response?.statusCode == 401) {
          _needsAccountMigration = true;
          await _requestEmailCode(email);
          return;
        }
        if (localPasswordValid &&
            response == null &&
            user?.passwordHash != null) {
          await JengaDB.instance.login(email, password);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Signed in offline. Stock will sync when the connection returns.'),
              ),
            );
            widget.onSuccess();
          }
          return;
        }
        if (response?.statusCode == 429) {
          throw FormatException(
            response?.data['message'] as String? ??
                'Too many sign-in attempts. Try again later.',
          );
        }
        if (user?.passwordHash == null &&
            user != null &&
            response?.statusCode != 429) {
          _needsAccountMigration = true;
          await _requestEmailCode(email);
          return;
        }
        if (response?.statusCode == 401 || !localPasswordValid) {
          throw const FormatException('Email or password is incorrect.');
        }
        throw const FormatException(
          'Could not reach JengaBiz. Check your connection and try again.',
        );
      }

      if (isSignUp && _referralCodeCtrl.text.trim().isNotEmpty) {
        final location =
            await LocationBiometricService.instance.detectReferralLocation();
        if (location == null) {
          throw const FormatException(
            'Turn on Location and allow access to detect your county for this referral.',
          );
        }
        if (location.countryCode != 'KE') {
          throw const FormatException(
            'JengaBiz referrals are currently available in Kenya only.',
          );
        }
        _detectedReferralCounty = location.county;
      } else {
        _detectedReferralCounty = null;
      }

      await _requestEmailCode(email);
    } catch (e) {
      if (mounted) {
        final message = switch (e) {
          FormatException(:final message) => message,
          HttpException(:final message) => message,
          _ => 'Something went wrong. Please try again.',
        };
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestEmailCode(String email) async {
    final response = await JengaApiService.instance.requestEmailOtp(
      email,
      purpose: _isPasswordReset ? 'password_reset' : 'account_verification',
    );
    if (response?['success'] != true) {
      if (response?['code'] == 'ACCOUNT_SUSPENDED') {
        _applySuspensionSupport(response?['support']);
      }
      throw HttpException(response?['message'] as String? ??
          'Could not send an email code. Check your connection and try again.');
    }
    if (!mounted) return;
    setState(() {
      isVerifyingCode = true;
      _otpCtrl.clear();
      _error = null;
    });
  }

  void _startPasswordReset() {
    setState(() {
      isSignUp = false;
      isVerifyingCode = false;
      _isPasswordReset = true;
      _accountSuspended = false;
      _resetOtpVerified = false;
      _resetVerificationToken = null;
      _needsAccountMigration = false;
      _passwordCtrl.clear();
      _confirmPasswordCtrl.clear();
      _otpCtrl.clear();
      _error = null;
    });
  }

  Future<void> _completePasswordReset() async {
    final password = _passwordCtrl.text;
    if (password.length < 8) {
      throw const FormatException('Use a password with at least 8 characters.');
    }
    if (password != _confirmPasswordCtrl.text) {
      throw const FormatException('The new passwords do not match.');
    }
    final verificationToken = _resetVerificationToken;
    if (verificationToken == null) {
      throw const FormatException(
          'Verify your email before changing password.');
    }

    final email = _emailCtrl.text.trim().toLowerCase();
    final response = await JengaApiService.instance.resetAccountPassword(
      email: email,
      verificationToken: verificationToken,
      newPassword: password,
    );
    if (response?.succeeded != true) {
      if (response?.data['code'] == 'ACCOUNT_SUSPENDED') {
        _applySuspensionSupport(response?.data['support']);
      }
      throw FormatException(
        response?.data['message'] as String? ??
            'Could not reset your password. Request a new email code and try again.',
      );
    }

    final api = JengaApiService.instance;
    if (api.sessionEmail == email) await api.clearSession();
    if (!mounted) return;
    setState(() {
      _isPasswordReset = false;
      _resetOtpVerified = false;
      _resetVerificationToken = null;
      isVerifyingCode = false;
      _passwordCtrl.clear();
      _confirmPasswordCtrl.clear();
      _otpCtrl.clear();
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password reset. Sign in with your new password.'),
        backgroundColor: Color(0xFF1E6BFF),
      ),
    );
  }

  void _handleBack() {
    if (isVerifyingCode) {
      setState(() {
        isVerifyingCode = false;
        _otpCtrl.clear();
        _error = null;
      });
      return;
    }
    if (_isPasswordReset) {
      setState(() {
        _isPasswordReset = false;
        _resetOtpVerified = false;
        _resetVerificationToken = null;
        _passwordCtrl.clear();
        _confirmPasswordCtrl.clear();
        _error = null;
      });
      return;
    }
    widget.onBack();
  }

  Future<bool> _activateRemoteAccount(
    Map<String, dynamic> response,
    String password,
  ) async {
    final token = response['sessionToken'];
    final profile = response['user'];
    if (token is! String || profile is! Map) {
      throw const FormatException(
          'JengaBiz returned an incomplete sign-in response.');
    }
    await JengaApiService.instance.saveSession(
      token,
      email: profile['email'] as String? ?? '',
    );
    await JengaDB.instance.persistAuthenticatedAccount(
      profile: Map<String, dynamic>.from(profile),
      password: password,
    );
    unawaited(FirebasePushService.instance.initialize());
    return JengaDB.instance.syncStockWithServer();
  }

  Future<void> _verifyOtpAndCreateAccount() async {
    if (isSignUp && !_acceptedTerms) {
      setState(() => _error =
          'Agree to the Terms of Use and Privacy Policy to create an account.');
      return;
    }
    final inputCode = _otpCtrl.text.trim();
    if (inputCode.isEmpty) {
      setState(() => _error = 'Please enter the 6-digit verification code');
      return;
    }

    if (!RegExp(r'^\d{6}$').hasMatch(inputCode)) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _accountSuspended = false;
    });

    try {
      final verificationToken = await JengaApiService.instance.verifyEmailOtp(
        _emailCtrl.text.trim(),
        inputCode,
      );
      if (verificationToken == null) {
        throw const FormatException(
            'That code is invalid or expired. Request another code and try again.');
      }

      if (_isPasswordReset) {
        if (!mounted) return;
        setState(() {
          _resetVerificationToken = verificationToken;
          _resetOtpVerified = true;
          isVerifyingCode = false;
          _passwordCtrl.clear();
          _confirmPasswordCtrl.clear();
          _error = null;
        });
        return;
      }

      final localUser = JengaDB.instance.findUser(_emailCtrl.text.trim());
      final profileName =
          isSignUp ? _nameCtrl.text.trim() : localUser?.name ?? '';
      final profileShop =
          isSignUp ? _shopCtrl.text.trim() : localUser?.shopName ?? '';
      final profilePhone =
          isSignUp ? _phoneCtrl.text.trim() : localUser?.phone ?? '';
      if (profileName.isEmpty || profileShop.isEmpty) {
        throw const FormatException(
          'This device has no saved shop profile for that email. Create a new account or contact support.',
        );
      }

      final migrationItems =
          !isSignUp && _needsAccountMigration && localUser != null
              ? await JengaDB.instance.stockForAccount(localUser.id)
              : <Map<String, dynamic>>[];
      final response = await JengaApiService.instance.createAccount(
        email: _emailCtrl.text.trim(),
        verificationToken: verificationToken,
        name: profileName,
        shopName: profileShop,
        phone: profilePhone,
        county: isSignUp ? _detectedReferralCounty ?? '' : '',
        referralCode:
            isSignUp ? _referralCodeCtrl.text.trim().toUpperCase() : '',
        password: _passwordCtrl.text,
        items: migrationItems,
        migrate: _needsAccountMigration,
      );
      if (response?.succeeded != true) {
        throw FormatException(
          response?.data['message'] as String? ??
              'Could not save the account. Check your connection and request a new email code.',
        );
      }
      if (isSignUp) await _recordTermsAcceptance();
      final stockSynced = await _activateRemoteAccount(
        response!.data,
        _passwordCtrl.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isSignUp
                ? 'Email verified. Your account and stock are saved.'
                : 'Your account and stock are now saved to JengaBiz.'),
            backgroundColor: const Color(0xFF1E6BFF),
          ),
        );
      }
      if (!stockSynced && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Signed in. Stock sync will retry when the connection returns.'),
          ),
        );
      }
      if (mounted) {
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FormatException
            ? e.message
            : 'Could not verify your account. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordTermsAcceptance() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt('jengabiz_terms_acceptance_version', 1);
      await preferences.setString(
        'jengabiz_terms_acceptance_utc',
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Account creation must not fail if the local acknowledgement cannot be saved.
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _loading = true;
      _error = null;
      _accountSuspended = false;
    });

    try {
      final response = await JengaApiService.instance.requestEmailOtp(
        _emailCtrl.text.trim(),
        purpose: _isPasswordReset ? 'password_reset' : 'account_verification',
      );
      if (response?['success'] != true) {
        if (response?['code'] == 'ACCOUNT_SUSPENDED') {
          _applySuspensionSupport(response?['support']);
        }
        throw HttpException(response?['message'] as String? ??
            'Could not resend your email code. Check your connection and try again.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('A new verification code was sent to your email.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e is HttpException ? e.message : 'Could not resend your code.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySuspensionSupport(dynamic rawSupport) {
    _accountSuspended = true;
    if (rawSupport is! Map) return;
    final name = rawSupport['name'];
    final adminName = rawSupport['adminName'];
    final email = rawSupport['email'];
    final phones = rawSupport['phoneNumbers'];
    if (name is String && name.trim().isNotEmpty) {
      _supportName = name.trim();
    }
    if (adminName is String && adminName.trim().isNotEmpty) {
      _supportAdminName = adminName.trim();
    }
    if (email is String && email.trim().isNotEmpty) {
      _supportEmail = email.trim();
    }
    if (phones is List) {
      final values = phones
          .whereType<String>()
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (values.isNotEmpty) _supportPhoneNumbers = values;
    }
  }

  String _internationalSupportNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) return '+254${digits.substring(1)}';
    if (digits.startsWith('254')) return '+$digits';
    return '+$digits';
  }

  Future<void> _launchSupport(Uri uri, String fallbackText) async {
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        await Clipboard.setData(ClipboardData(text: fallbackText));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact copied to clipboard.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: fallbackText));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact copied to clipboard.')),
      );
    }
  }

  Future<void> _requestSuspensionReview() async {
    if (_supportRequestSending) return;
    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send a review request?'),
        content: Text(
          'Your name, shop, email and phone number will be sent to $_supportName so the admin team can review this suspended account. Your password is used only to verify the account and is never sent to support.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (shouldSend != true || !mounted) return;

    setState(() => _supportRequestSending = true);
    try {
      final response =
          await JengaApiService.instance.requestSuspendedAccountSupport(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (response?.succeeded == true) {
        final ticketId = response?.data['ticketId'] as String?;
        if (!mounted) return;
        setState(() {
          _supportTicketId = ticketId;
          _error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ticketId == null
                ? 'Review request sent to MF Technologies.'
                : 'Review request sent. Reference: $ticketId'),
          ),
        );
      } else {
        final message = response?.data['message'] as String? ??
            'Could not send the review request. Use the contact options below.';
        if (response?.data['support'] != null) {
          _applySuspensionSupport(response?.data['support']);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not reach MF Technologies. Use the contact options below.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _supportRequestSending = false);
    }
  }

  Widget _errorPanel() {
    final error = _error;
    if (error == null && !_accountSuspended) return const SizedBox.shrink();
    final requestSent = _accountSuspended && _supportTicketId != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: requestSent && error == null
            ? const Color(0xFFEAF7EF)
            : const Color(0xFFFFECEB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null)
            Text(error,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          if (_accountSuspended) ...[
            const SizedBox(height: 10),
            Text(
              'Contact $_supportName support. Your case is handled by $_supportAdminName.',
              style: const TextStyle(
                color: Color(0xFF343247),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            if (_supportTicketId case final ticketId?) ...[
              Text(
                'Request sent to MF Technologies · $ticketId',
                style: const TextStyle(
                  color: Color(0xFF197346),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed:
                      _supportRequestSending ? null : _requestSuspensionReview,
                  icon: _supportRequestSending
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.outgoing_mail, size: 17),
                  label: Text(_supportRequestSending
                      ? 'Sending request…'
                      : 'Send support request'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1E6BFF),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton.icon(
                  onPressed: () => _launchSupport(
                    Uri(scheme: 'mailto', path: _supportEmail),
                    _supportEmail,
                  ),
                  icon: const Icon(Icons.email_outlined, size: 16),
                  label: Text(_supportEmail),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1E6BFF),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                for (final phone in _supportPhoneNumbers)
                  TextButton.icon(
                    onPressed: () => _launchSupport(
                      Uri(
                        scheme: 'tel',
                        path: _internationalSupportNumber(phone),
                      ),
                      phone,
                    ),
                    icon: const Icon(Icons.call_outlined, size: 16),
                    label: Text(phone),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1E6BFF),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _signInWithBiometrics() async {
    setState(() {
      _loading = true;
      _error = null;
      _accountSuspended = false;
    });

    try {
      final authenticated =
          await LocationBiometricService.instance.authenticateBiometric(
        reason: 'Verify your identity to open JengaBiz',
      );
      if (!authenticated || !await JengaDB.instance.loginWithBiometrics()) {
        throw const FormatException('Fingerprint sign-in was not completed.');
      }
      if (mounted) widget.onSuccess();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FormatException
            ? e.message
            : 'Fingerprint sign-in is unavailable. Use your password instead.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showTerms() => showLegalDocument(context, jengaBizTerms);

  void _showPrivacy() => showLegalDocument(context, jengaBizPrivacy);

  @override
  Widget build(BuildContext context) {
    const kBlue = Color(0xFF1E6BFF);
    final resetEmailStage = _isPasswordReset && !_resetOtpVerified;
    final resetPasswordStage = _isPasswordReset && _resetOtpVerified;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _handleBack,
                ),
              ),
              const SizedBox(height: 8),

              // Logo Mark
              Image.asset(
                'assets/jengabiz_mark.png',
                height: 52,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),

              if (isVerifyingCode) ...[
                const Text(
                  'Verify Your Email',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Color(0xFF17162A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit verification code sent to\n${_emailCtrl.text.trim()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF777487), height: 1.4),
                ),
                const SizedBox(height: 24),

                if (_error != null ||
                    (_accountSuspended && _supportTicketId != null))
                  _errorPanel(),

                _field(
                  label: '6-Digit Verification Code',
                  controller: _otpCtrl,
                  icon: Icons.mark_email_read_outlined,
                  hint: '123456',
                  keyboard: TextInputType.number,
                ),
                const SizedBox(height: 24),

                // Verify Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _loading ? null : _verifyOtpAndCreateAccount,
                    borderRadius: BorderRadius.circular(28),
                    child: Ink(
                      height: 56,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E6BFF), Color(0xFF2563EB)],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x351E6BFF),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                _isPasswordReset
                                    ? 'Verify Email'
                                    : 'Verify Code & Open JengaBiz',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                TextButton(
                  onPressed: _loading ? null : _resendCode,
                  child: const Text(
                    'Did not receive the email? Resend code',
                    style: TextStyle(
                      color: kBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ] else ...[
                // SIGN UP / SIGN IN TABS
                Text(
                  _isPasswordReset
                      ? resetPasswordStage
                          ? 'Create New Password'
                          : 'Reset Password'
                      : isSignUp
                          ? 'Create Shop Account'
                          : 'Sign In',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Color(0xFF17162A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isPasswordReset
                      ? resetPasswordStage
                          ? 'Set a new password for ${_emailCtrl.text.trim()}'
                          : 'Enter your account email to receive a verification code.'
                      : isSignUp
                          ? 'Set up your business profile to start managing stock'
                          : 'Sign in to access your shop ledger and inventory',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF777487)),
                ),
                const SizedBox(height: 24),

                if (!_isPasswordReset) ...[
                  // Segmented Toggle
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EEF8),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              if (!isSignUp) {
                                _nameCtrl.clear();
                                _shopCtrl.clear();
                                _phoneCtrl.clear();
                                _referralCodeCtrl.clear();
                                _detectedReferralCounty = null;
                                _emailCtrl.clear();
                                _passwordCtrl.clear();
                                _otpCtrl.clear();
                                _acceptedTerms = false;
                              }
                              isSignUp = true;
                              _needsAccountMigration = false;
                              _accountSuspended = false;
                              _error = null;
                            }),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSignUp
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: isSignUp
                                    ? const [
                                        BoxShadow(
                                          color: Color(0x15000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'New Account',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: isSignUp
                                      ? kBlue
                                      : const Color(0xFF777487),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              isSignUp = false;
                              _acceptedTerms = false;
                              _needsAccountMigration = false;
                              _accountSuspended = false;
                              _error = null;
                            }),
                            child: Container(
                              decoration: BoxDecoration(
                                color: !isSignUp
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: !isSignUp
                                    ? const [
                                        BoxShadow(
                                          color: Color(0x15000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Sign In',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: !isSignUp
                                      ? kBlue
                                      : const Color(0xFF777487),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                if (_error != null ||
                    (_accountSuspended && _supportTicketId != null))
                  _errorPanel(),

                if (isSignUp) ...[
                  _field(
                    label: 'Full Name',
                    controller: _nameCtrl,
                    icon: Icons.person_outline_rounded,
                    hint: 'e.g. Alex Smith',
                  ),
                  const SizedBox(height: 14),
                  _field(
                    label: 'Shop / Business Name',
                    controller: _shopCtrl,
                    icon: Icons.storefront_outlined,
                    hint: 'e.g. Nairobi Central Duka',
                  ),
                  const SizedBox(height: 14),
                  _field(
                    label: 'Phone Number (optional)',
                    controller: _phoneCtrl,
                    icon: Icons.phone_outlined,
                    hint: 'Optional contact number',
                    keyboard: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    label: 'Referral Code (optional)',
                    controller: _referralCodeCtrl,
                    icon: Icons.card_giftcard_outlined,
                    hint: 'Enter your invite code',
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_referralCodeCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Your county is detected from your device location.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF777487)),
                    ),
                  ],
                  const SizedBox(height: 14),
                ],

                if (!resetPasswordStage) ...[
                  _field(
                    label: 'Email Address',
                    controller: _emailCtrl,
                    icon: Icons.mail_outline_rounded,
                    hint: 'alex@jengabiz.com',
                    keyboard: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE4E6F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_outlined,
                            size: 20, color: Color(0xFF1E6BFF)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Email verified: ${_emailCtrl.text.trim()}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF4A475C)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                if (!resetEmailStage) ...[
                  _field(
                    label: _isPasswordReset ? 'New Password' : 'Password',
                    controller: _passwordCtrl,
                    icon: Icons.lock_outline_rounded,
                    hint: 'At least 8 characters',
                    obscure: true,
                    keyboard: TextInputType.visiblePassword,
                  ),
                  if (resetPasswordStage) ...[
                    const SizedBox(height: 14),
                    _field(
                      label: 'Repeat New Password',
                      controller: _confirmPasswordCtrl,
                      icon: Icons.lock_outline_rounded,
                      hint: 'Enter the new password again',
                      obscure: true,
                      keyboard: TextInputType.visiblePassword,
                    ),
                  ],
                ],

                if (isSignUp) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _acceptedTerms,
                    activeColor: kBlue,
                    onChanged: _loading
                        ? null
                        : (accepted) => setState(() {
                              _acceptedTerms = accepted ?? false;
                              if (_acceptedTerms) _error = null;
                            }),
                    title: const Text(
                      'I agree to the Terms of Use and Privacy Policy.',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'By continuing, you agree that JengaBiz stores your account and stock data securely.',
                      style: TextStyle(fontSize: 10, color: Color(0xFF777487)),
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Submit Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _loading ? null : _submit,
                    borderRadius: BorderRadius.circular(28),
                    child: Ink(
                      height: 56,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E6BFF), Color(0xFF2563EB)],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x351E6BFF),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                _isPasswordReset
                                    ? resetPasswordStage
                                        ? 'Reset Password'
                                        : 'Send Email Code'
                                    : isSignUp
                                        ? 'Create Account & Verify Email'
                                        : 'Sign In',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),

                if (!isSignUp && !_isPasswordReset) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.center,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _loading ? null : _startPasswordReset,
                          style: TextButton.styleFrom(
                            foregroundColor: kBlue,
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 5),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'Forgot password?',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        if (_canUseBiometrics &&
                            JengaDB.instance.users.isNotEmpty)
                          TextButton(
                            onPressed: _loading ? null : _signInWithBiometrics,
                            style: TextButton.styleFrom(
                              foregroundColor: kBlue,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 5),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text(
                              'Sign in with fingerprint',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Read:',
                      style: TextStyle(fontSize: 11, color: Color(0xFF777487)),
                    ),
                    TextButton(
                      onPressed: _showTerms,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Terms of Use',
                          style: TextStyle(fontSize: 11)),
                    ),
                    const Text('and',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFF777487))),
                    TextButton(
                      onPressed: _showPrivacy,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Privacy Policy',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your account and stock sync securely and stay cached offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Color(0xFF8E8B9E)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4A475C),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE4E6F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0817162A),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            obscureText: obscure,
            keyboardType: keyboard,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 20, color: const Color(0xFF1E6BFF)),
              hintText: hint,
              hintStyle:
                  const TextStyle(color: Color(0xFFB0ADC0), fontSize: 13),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
