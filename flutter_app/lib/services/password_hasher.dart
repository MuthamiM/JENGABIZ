import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const _passwordIterations = 120000;

Future<String> hashPassword(String password, String salt) => compute(
      _derivePasswordHash,
      <String, String>{'password': password, 'salt': salt},
    );

String _derivePasswordHash(Map<String, String> input) {
  final hmac = Hmac(sha256, utf8.encode(input['password']!));
  final salt = utf8.encode(input['salt']!);
  var block = hmac.convert(<int>[...salt, 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);

  for (var iteration = 1; iteration < _passwordIterations; iteration++) {
    block = hmac.convert(block).bytes;
    for (var index = 0; index < result.length; index++) {
      result[index] ^= block[index];
    }
  }

  return result.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
