import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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

  final _nameCtrl = TextEditingController();
  final _shopCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _referralCodeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _loading = false;
  bool _canUseBiometrics = false;
  String? _detectedReferralCounty;
  String? _error;

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
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
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
    final response = await JengaApiService.instance.requestEmailOtp(email);
    if (response?['success'] != true) {
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

  Future<void> _resendCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await JengaApiService.instance
          .requestEmailOtp(_emailCtrl.text.trim());
      if (response?['success'] != true) {
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

  Future<void> _signInWithBiometrics() async {
    setState(() {
      _loading = true;
      _error = null;
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

  void _showPolicy(String title, List<String> paragraphs) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: paragraphs
                        .map((paragraph) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(paragraph,
                                  style: const TextStyle(height: 1.5)),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTerms() => _showPolicy('Terms of Use', const [
        'JengaBiz provides tools for recording and reviewing shop inventory, sales, and business activity. These terms apply when you create an account or use the app.',
        'Give accurate account details and keep your password and device secure. You are responsible for activity performed through your account and for limiting access to your shop records.',
        'Use JengaBiz only for lawful business purposes and only enter information you are authorized to manage. Do not attempt to disrupt the service, access another person’s account, or misuse verification codes.',
        'You own the business information you enter. You are responsible for checking your entries and maintaining any backup you need, especially before changing devices or clearing app data.',
        'Sales totals, stock summaries, and other calculations are recordkeeping aids. Review them against your source documents before making financial, tax, legal, or purchasing decisions; JengaBiz does not provide professional advice.',
        'JengaBiz referral points are available in Kenya only. A new account that enters a valid referral code and verifies its email can award 50 points when both shops are in the same county, or 75 points when they are in different counties. Each new account can count once. Redemption is not available yet.',
        'Some features need an internet connection and may be unavailable during maintenance, provider outages, or network interruptions. You are responsible for compatible devices and data charges.',
        'JengaBiz and its design, name, and software remain protected by applicable intellectual property rights. You may use the app for your own business while following these terms.',
        'We may restrict access when needed to protect accounts, users, or the service, including when there is suspected fraud, abuse, or a security risk. You may stop using the app at any time.',
        'The app is provided as a business recordkeeping tool. To the extent permitted by law, you are responsible for decisions made using its records and summaries.',
        'We may revise these terms as the service changes. The current version is shown here; continued use after an update means you accept the revised terms. For support, contact MF Technologies through mftechnologies.org.',
      ]);

  void _showPrivacy() => _showPolicy('Privacy Policy', const [
        'JengaBiz uses your name, shop name, email address, optional phone number, and a salted password hash to create and protect your account. Passwords are never stored in plain text; the server uses scrypt and the app keeps a separate PBKDF2 hash for offline sign-in.',
        'When you request account verification, your email address and one-time code are sent through our email delivery provider so it can deliver the message. Codes expire after 10 minutes, can be used once, and are limited to reduce abuse.',
        'Your shop profile and inventory are stored in the JengaBiz account database and cached on your device so the app can work during brief network interruptions. Inventory changes sync to the account database when connected. The app may also cache data on your device for faster screens and the stock widget.',
        'Location access is optional. If you allow it, the app uses your location to estimate the nearest supply hub. You can deny or revoke location access in your device settings.',
        'Fingerprint or face authentication is handled by your device operating system. JengaBiz receives only the success or failure result; the app does not receive or store your fingerprint or face data.',
        'We use account and business information to provide app features, verify email ownership, protect accounts, and respond to support requests. We do not sell your personal information.',
        'If you use Refer & Earn, JengaBiz uses your phone location and the device geocoder to detect whether you are in Kenya and identify your county. GPS coordinates are not sent to JengaBiz; the JengaBiz service receives the detected country code and county needed to apply the referral rules.',
        'Information may be processed by infrastructure and email providers that help operate the service. They receive only the information needed to provide their service and protect it.',
        'Changes made offline remain on that device until they sync. If the device is lost, the app is removed, or its storage is cleared before sync, those pending changes may be lost. Contact MF Technologies for account or data support.',
        'We use reasonable safeguards, including encrypted network connections for public services and salted password hashing. No device or online service can be guaranteed completely secure, so keep your device locked and do not share verification codes.',
        'We retain verification codes only briefly and remove them after successful use or expiry. Other information is kept while needed to provide the app or meet service and legal requirements.',
        'For privacy questions or account support, contact MF Technologies through mftechnologies.org.',
      ]);

  @override
  Widget build(BuildContext context) {
    const kBlue = Color(0xFF1E6BFF);

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
                  onPressed: isVerifyingCode
                      ? () => setState(() => isVerifyingCode = false)
                      : widget.onBack,
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

                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFECEB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),

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
                            : const Text(
                                'Verify Code & Open JengaBiz',
                                style: TextStyle(
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
                  isSignUp ? 'Create Shop Account' : 'Sign In',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Color(0xFF17162A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isSignUp
                      ? 'Set up your business profile to start managing stock'
                      : 'Sign in to access your shop ledger and inventory',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF777487)),
                ),
                const SizedBox(height: 24),

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
                            }
                            isSignUp = true;
                            _needsAccountMigration = false;
                            _error = null;
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  isSignUp ? Colors.white : Colors.transparent,
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
                                color:
                                    isSignUp ? kBlue : const Color(0xFF777487),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            isSignUp = false;
                            _needsAccountMigration = false;
                            _error = null;
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color:
                                  !isSignUp ? Colors.white : Colors.transparent,
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
                                color:
                                    !isSignUp ? kBlue : const Color(0xFF777487),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFECEB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),

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

                _field(
                  label: 'Email Address',
                  controller: _emailCtrl,
                  icon: Icons.mail_outline_rounded,
                  hint: 'alex@jengabiz.com',
                  keyboard: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),
                _field(
                  label: 'Password',
                  controller: _passwordCtrl,
                  icon: Icons.lock_outline_rounded,
                  hint: 'At least 8 characters',
                  obscure: true,
                  keyboard: TextInputType.visiblePassword,
                ),

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
                                isSignUp
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

                if (!isSignUp &&
                    _canUseBiometrics &&
                    JengaDB.instance.users.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : _signInWithBiometrics,
                    style: TextButton.styleFrom(
                      foregroundColor: kBlue,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Sign in with fingerprint',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'By continuing, you agree to our',
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
