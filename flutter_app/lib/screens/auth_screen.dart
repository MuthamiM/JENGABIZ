import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/email_service.dart';
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
  bool isVerifyingEmail = false;

  final _nameCtrl = TextEditingController();
  final _shopCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _generatedOtp;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    if (JengaDB.instance.users.isNotEmpty) {
      isSignUp = false;
      final lastUser = JengaDB.instance.users.first;
      _emailCtrl.text = lastUser.email;
    }
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final available = await LocationBiometricService.instance.canUseBiometrics();
    if (mounted) {
      setState(() => _canUseBiometrics = available);
      if (available && JengaDB.instance.users.isNotEmpty) {
        // Automatically prompt biometrics so user doesn't have to log in manually each time
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _signInWithBiometrics();
        });
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shopCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _pinCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (isSignUp) {
        if (_nameCtrl.text.trim().isEmpty || _shopCtrl.text.trim().isEmpty) {
          setState(() {
            _error = 'Please enter your full name and shop name';
            _loading = false;
          });
          return;
        }
        if (_emailCtrl.text.trim().isEmpty) {
          setState(() {
            _error = 'Please enter your email address for account verification';
            _loading = false;
          });
          return;
        }

        // Generate 6-digit OTP and send via Resend API
        final code = EmailService.generateCode();
        _generatedOtp = code;

        final result = await EmailService.sendVerificationEmail(
          recipientEmail: _emailCtrl.text.trim(),
          shopName: _shopCtrl.text.trim(),
          code: code,
        );

        if (!result.success) {
          setState(() {
            _error = result.message;
            _loading = false;
          });
          return;
        }

        setState(() {
          isVerifyingEmail = true;
          _loading = false;
          _error = null;
        });
      } else {
        // Sign In: User MUST have an account created first
        final query = _emailCtrl.text.trim().isNotEmpty
            ? _emailCtrl.text.trim()
            : _phoneCtrl.text.trim();

        if (query.isEmpty) {
          setState(() {
            _error = 'Please enter your email or phone to sign in';
            _loading = false;
          });
          return;
        }

        final ok = await JengaDB.instance.login(query);
        if (ok) {
          if (mounted) widget.onSuccess();
        } else {
          setState(() {
            _error = 'No account found. You must create an account first.';
            _loading = false;
          });
          return;
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtpAndCreateAccount() async {
    final inputCode = _otpCtrl.text.trim();
    if (inputCode.isEmpty) {
      setState(() => _error = 'Please enter the 6-digit verification code');
      return;
    }

    if (inputCode != _generatedOtp) {
      setState(() => _error = 'Invalid verification code. Please check and try again.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await JengaDB.instance.createAccount(
        name: _nameCtrl.text.trim(),
        shopName: _shopCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _pinCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified and shop account created successfully!'),
            backgroundColor: Color(0xFF1E6BFF),
          ),
        );
        widget.onSuccess();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_emailCtrl.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final newCode = EmailService.generateCode();
    _generatedOtp = newCode;

    final res = await EmailService.sendVerificationEmail(
      recipientEmail: _emailCtrl.text.trim(),
      shopName: _shopCtrl.text.trim().isNotEmpty ? _shopCtrl.text.trim() : 'My Duka',
      code: newCode,
    );

    setState(() {
      _loading = false;
      if (!res.success) {
        _error = res.message;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.success
              ? 'Verification code resent to your email'
              : (res.message ?? 'Failed to resend code')),
          backgroundColor: res.success ? const Color(0xFF1E6BFF) : const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _signInWithBiometrics() async {
    setState(() => _error = null);

    final users = JengaDB.instance.users;
    if (users.isEmpty) {
      setState(() {
        _error = 'No registered account found. You must create an account first.';
      });
      return;
    }

    final success = await LocationBiometricService.instance.authenticateBiometric(
      reason: 'Scan fingerprint or Face ID to sign in to JengaBiz',
    );

    if (success) {
      final user = users.first;
      await JengaDB.instance.login(user.email.isNotEmpty ? user.email : user.phone);
      if (mounted) widget.onSuccess();
    } else {
      setState(() {
        _error = 'Biometric verification cancelled or not recognized';
      });
    }
  }

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
                  onPressed: isVerifyingEmail
                      ? () => setState(() => isVerifyingEmail = false)
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

              if (isVerifyingEmail) ...[
                // EMAIL VERIFICATION VIEW
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
                  'Enter the 6-digit code sent to\n${_emailCtrl.text.trim()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF777487), height: 1.4),
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
                    'Did not receive code? Resend Email',
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
                  isSignUp ? 'Create Shop Account' : 'Welcome Back',
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
                  style: const TextStyle(fontSize: 13, color: Color(0xFF777487)),
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
                            isSignUp = true;
                            _error = null;
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSignUp ? Colors.white : Colors.transparent,
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
                                color: isSignUp ? kBlue : const Color(0xFF777487),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            isSignUp = false;
                            _error = null;
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: !isSignUp ? Colors.white : Colors.transparent,
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
                                color: !isSignUp ? kBlue : const Color(0xFF777487),
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

                if (!isSignUp && _canUseBiometrics && JengaDB.instance.users.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFDCE7FC)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0C1E6BFF),
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF4FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.fingerprint_rounded, color: kBlue, size: 26),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome back, ${JengaDB.instance.users.first.name}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF17162A)),
                                  ),
                                  const Text(
                                    'Biometric Unlock (Fingerprint or Face ID)',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF777487)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _signInWithBiometrics,
                            icon: const Icon(Icons.security_rounded, size: 18),
                            label: const Text(
                              'Touch Sensor / Face ID to Unlock',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: kBlue,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or sign in with PIN',
                          style: TextStyle(fontSize: 11, color: Color(0xFF8E8B9E)),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],

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
                    label: 'Phone Number',
                    controller: _phoneCtrl,
                    icon: Icons.phone_outlined,
                    hint: '+254 700 000 000',
                    keyboard: TextInputType.phone,
                  ),
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
                  label: 'Security PIN / Password',
                  controller: _pinCtrl,
                  icon: Icons.lock_outline_rounded,
                  hint: '4-digit PIN',
                  obscure: true,
                  keyboard: TextInputType.number,
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
                                    : 'Sign In to JengaBiz',
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

                if (!isSignUp && _canUseBiometrics) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _signInWithBiometrics,
                    icon: const Icon(Icons.fingerprint_rounded, color: kBlue, size: 22),
                    label: const Text(
                      'Sign In with Fingerprint / Face ID',
                      style: TextStyle(
                        color: kBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      side: const BorderSide(color: Color(0xFFBFDBFE), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                      backgroundColor: const Color(0xFFF0F5FF),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Text(
                  'All shop credentials and inventory are encrypted and stored safely',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFF8E8B9E)),
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
            obscureText: obscure,
            keyboardType: keyboard,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 20, color: const Color(0xFF1E6BFF)),
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFFB0ADC0), fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
