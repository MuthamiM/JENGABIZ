import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';

class SuspendedAccountHelpScreen extends StatefulWidget {
  const SuspendedAccountHelpScreen({
    super.key,
    required this.email,
    required this.supportName,
    required this.supportEmail,
    required this.supportPhoneNumbers,
  });

  final String email;
  final String supportName;
  final String supportEmail;
  final List<String> supportPhoneNumbers;

  @override
  State<SuspendedAccountHelpScreen> createState() =>
      _SuspendedAccountHelpScreenState();
}

class _SuspendedAccountHelpScreenState
    extends State<SuspendedAccountHelpScreen> {
  static const _blue = Color(0xFF1E6BFF);

  final _passwordController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _sending = false;
  String? _error;
  String? _ticketId;

  @override
  void dispose() {
    _passwordController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    if (_sending || _ticketId != null) return;
    final password = _passwordController.text;
    final reason = _reasonController.text.trim();
    if (password.length < 8) {
      setState(() => _error = 'Enter your current account password.');
      return;
    }
    if (reason.length < 20 || reason.length > 2000) {
      setState(() => _error =
          'Explain why the account should be reviewed in 20 to 2,000 characters.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final response =
          await JengaApiService.instance.requestSuspendedAccountSupport(
        email: widget.email,
        password: password,
        reason: reason,
      );
      if (!mounted) return;
      if (response?.succeeded == true) {
        setState(() {
          _ticketId = response?.data['ticketId'] as String? ?? 'Submitted';
          _passwordController.clear();
        });
      } else {
        setState(() {
          _error = response?.data['message'] as String? ??
              'Could not send your request. Try again or contact MF Technologies.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not reach MF Technologies. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openContact(Uri uri) async {
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the contact app.')),
      );
    }
  }

  String _internationalNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) return '+254${digits.substring(1)}';
    if (digits.startsWith('254')) return '+$digits';
    return '+$digits';
  }

  @override
  Widget build(BuildContext context) {
    final submitted = _ticketId != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      appBar: AppBar(
        title: const Text('Account review'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF17162A),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: submitted ? _successContent() : _requestContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _requestContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.support_agent_rounded, color: _blue, size: 34),
        const SizedBox(height: 14),
        const Text(
          'Request an account review',
          style: TextStyle(
            color: Color(0xFF17162A),
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tell MF Technologies why this suspended account should be reviewed for reactivation.',
          style: TextStyle(color: Color(0xFF777487), fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 22),
        const Text(
          'Account email',
          style: TextStyle(
            color: Color(0xFF343247),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        SelectableText(
          widget.email,
          style: const TextStyle(color: Color(0xFF17162A), fontSize: 15),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _reasonController,
          minLines: 5,
          maxLines: 8,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: 'Reason for reactivation',
            hintText: 'Explain what happened and why the account should be restored.',
            alignLabelWithHint: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDDE2F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _blue, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Current account password',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDDE2F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _blue, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Your account name, shop, registered contact details, and reason will be sent to MF Technologies. Your password is used only to verify your account with JengaBiz and is not included in the request. If your reason qualifies for reactivation, MF Technologies will contact you by email.',
          style: TextStyle(color: Color(0xFF777487), fontSize: 12, height: 1.5),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          _contactLinks(),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sending ? null : _sendRequest,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(_sending ? 'Sending request…' : 'Send review request'),
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _successContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.mark_email_read_outlined, color: _blue, size: 38),
        const SizedBox(height: 16),
        const Text(
          'Request sent',
          style: TextStyle(
            color: Color(0xFF17162A),
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${widget.supportName} will review your explanation. If it qualifies for reactivation, the team will contact ${widget.email} by email.',
          style: const TextStyle(color: Color(0xFF777487), fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 14),
        SelectableText(
          'Reference: $_ticketId',
          style: const TextStyle(
            color: Color(0xFF343247),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
            ),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _contactLinks() => Wrap(
        spacing: 4,
        runSpacing: 0,
        children: [
          TextButton.icon(
            onPressed: () => _openContact(
              Uri(scheme: 'mailto', path: widget.supportEmail),
            ),
            icon: const Icon(Icons.email_outlined, size: 16),
            label: Text(widget.supportEmail),
          ),
          for (final phone in widget.supportPhoneNumbers)
            TextButton.icon(
              onPressed: () => _openContact(
                Uri(scheme: 'tel', path: _internationalNumber(phone)),
              ),
              icon: const Icon(Icons.call_outlined, size: 16),
              label: Text(phone),
            ),
        ],
      );
}
