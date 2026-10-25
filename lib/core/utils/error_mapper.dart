import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns any exception into a short message that is safe to show a user.
/// Raw exception text is never displayed, except the messages our own
/// database functions raise on purpose (Postgres code P0001), which are
/// written for end users.
class ErrorMapper {
  ErrorMapper._();

  static const _fallback = 'Something went wrong. Please try again.';

  static String message(Object error) {
    if (error is AuthException) return _auth(error);
    if (error is PostgrestException) return _postgrest(error);
    if (error is StorageException) return _storage(error);
    if (error is AppException) return error.message;
    // Network failures: matched by type name / text so this file has no
    // dart:io dependency and works on both Windows and the web.
    final text = '${error.runtimeType} $error';
    if (error is TimeoutException ||
        text.contains('SocketException') ||
        text.contains('HttpException') ||
        text.contains('ClientException') ||
        text.contains('Failed host lookup') ||
        text.contains('XMLHttpRequest error') ||
        text.contains('Failed to fetch')) {
      return "Can't reach the server. Check your internet connection and try again.";
    }
    return _fallback;
  }

  static String _auth(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login credentials')) return 'Email or password is incorrect.';
    if (m.contains('email not confirmed')) return 'Please confirm your email address first – check your inbox.';
    if (m.contains('already registered') || m.contains('already been registered') || m.contains('user already exists')) {
      return 'An account with this email already exists.';
    }
    if (m.contains('database error saving new user')) {
      return 'We could not create your account. Check your company name and role and try again.';
    }
    if (m.contains('password should be') || m.contains('weak password')) {
      return 'Password is too weak. Use at least 8 characters with letters and numbers.';
    }
    if (m.contains('rate limit') || e.statusCode == '429') return 'Too many attempts. Please wait a minute and try again.';
    if (m.contains('invalid email') || m.contains('unable to validate email')) return 'Enter a valid email address.';
    if (m.contains('jwt') || m.contains('session')) return 'Your session has expired. Please log in again.';
    return 'Authentication failed. Please try again.';
  }

  static String _postgrest(PostgrestException e) {
    switch (e.code) {
      case 'P0001': // raised deliberately by our SQL functions/triggers
        return e.message;
      case '23505':
        if (e.message.contains('products_supplier_name')) return 'You already have a product with this name.';
        return 'This record already exists.';
      case '23514':
        return 'Some values are invalid or too long. Please review the form.';
      case '23503':
        return 'A referenced item no longer exists. Refresh and try again.';
      case '22P02':
      case '22003':
      case '22007':
      case '22008':
        return 'Some values have an invalid format.';
      case '42501':
        return "You don't have permission to do that.";
      case 'PGRST116':
        return 'The item was not found or you no longer have access to it.';
      case 'PGRST301':
      case 'PGRST303':
        return 'Your session has expired. Please log in again.';
    }
    if (e.message.contains('row-level security')) return "You don't have permission to do that.";
    return _fallback;
  }

  static String _storage(StorageException e) {
    final m = e.message.toLowerCase();
    if (m.contains('payload too large') || m.contains('maximum allowed size') || e.statusCode == '413') {
      return 'The file is too large.';
    }
    if (m.contains('mime') || m.contains('invalid_mime_type') || m.contains('not supported')) {
      return 'This file type is not allowed.';
    }
    if (m.contains('row-level security') || e.statusCode == '403') return "You don't have permission to upload this file.";
    if (m.contains('already exists') || e.statusCode == '409') return 'A file with this name already exists.';
    return 'The file could not be uploaded. Please try again.';
  }
}

/// App-level error with a message that is already user friendly.
class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}
