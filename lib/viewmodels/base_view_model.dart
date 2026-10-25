import 'package:flutter/foundation.dart';

import '../core/utils/error_mapper.dart';

/// Shared loading / error handling for every screen ViewModel.
///
/// * [isLoading] + [loadError]  – the screen's initial data load.
/// * [isBusy]    + [actionError] – a user action (save, delete, accept…).
/// Errors are always converted to friendly text by [ErrorMapper].
abstract class BaseViewModel extends ChangeNotifier {
  bool _isLoading = false;
  bool _isBusy = false;
  String? _loadError;
  String? _actionError;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  bool get isBusy => _isBusy;
  String? get loadError => _loadError;
  String? get actionError => _actionError;
  bool get isDisposed => _disposed;

  /// Runs the initial load. Returns null when it failed.
  @protected
  Future<T?> runLoad<T>(Future<T> Function() action) async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      return await action();
    } catch (e) {
      _loadError = ErrorMapper.message(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Runs a user action. Returns false when it failed (see [actionError]).
  @protected
  Future<bool> runAction(Future<void> Function() action) async {
    if (_isBusy) return false; // ignore double clicks
    _isBusy = true;
    _actionError = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _actionError = ErrorMapper.message(e);
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @protected
  void setActionError(String? message) {
    _actionError = message;
    notifyListeners();
  }

  void clearActionError() {
    if (_actionError == null) return;
    _actionError = null;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
