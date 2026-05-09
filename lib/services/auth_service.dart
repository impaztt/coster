import 'package:supabase_flutter/supabase_flutter.dart';

import 'save_service.dart';

class AuthStatus {
  final String? userId;
  final String? email;
  final bool isAnonymous;

  const AuthStatus({
    required this.userId,
    required this.email,
    required this.isAnonymous,
  });

  bool get isSignedIn => userId != null;
  bool get isLinkedAccount => isSignedIn && !isAnonymous;

  String get shortUserId {
    final id = userId;
    if (id == null || id.length <= 8) return id ?? '-';
    return '${id.substring(0, 8)}...';
  }

  factory AuthStatus.fromUser(User? user) => AuthStatus(
        userId: user?.id,
        email: user?.email,
        isAnonymous: user?.isAnonymous ?? false,
      );
}

class AuthActionResult {
  final bool ok;
  final String message;

  const AuthActionResult({required this.ok, required this.message});
}

enum SocialSignInProvider {
  google,
  apple;

  OAuthProvider get oauthProvider => switch (this) {
        SocialSignInProvider.google => OAuthProvider.google,
        SocialSignInProvider.apple => OAuthProvider.apple,
      };

  String get label => switch (this) {
        SocialSignInProvider.google => 'Google',
        SocialSignInProvider.apple => 'Apple',
      };
}

class AuthService {
  SupabaseClient get _client => Supabase.instance.client;
  final _saveService = SaveService();

  AuthStatus get currentStatus => AuthStatus.fromUser(_client.auth.currentUser);

  Stream<AuthStatus> watchStatus() async* {
    yield currentStatus;
    await for (final _ in _client.auth.onAuthStateChange) {
      yield currentStatus;
    }
  }

  Future<AuthActionResult> signInWithSocial(
    SocialSignInProvider provider,
  ) async {
    try {
      await _saveService.markPendingAccountLogin();
      final launched = await _client.auth.signInWithOAuth(
        provider.oauthProvider,
      );
      if (!launched) await _saveService.clearPendingAccountLogin();
      return AuthActionResult(
        ok: launched,
        message: launched
            ? '${provider.label} 로그인 화면으로 이동합니다'
            : '${provider.label} 로그인 창을 열지 못했어요',
      );
    } on AuthException catch (e) {
      return AuthActionResult(ok: false, message: _authErrorMessage(e));
    } catch (_) {
      return AuthActionResult(
        ok: false,
        message: '${provider.label} 로그인 중 오류가 발생했어요',
      );
    }
  }

  Future<AuthActionResult> signOutToGuest() async {
    try {
      await _client.auth.signOut();
      await _client.auth.signInAnonymously();
      return const AuthActionResult(
        ok: true,
        message: '게스트 상태로 전환됐어요',
      );
    } on AuthException catch (e) {
      return AuthActionResult(ok: false, message: _authErrorMessage(e));
    } catch (_) {
      return const AuthActionResult(
        ok: false,
        message: '로그아웃 중 오류가 발생했어요',
      );
    }
  }

  String _authErrorMessage(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
      return '이메일 또는 비밀번호가 맞지 않아요';
    }
    if (msg.contains('already') || msg.contains('registered')) {
      return '이미 사용 중인 이메일이에요';
    }
    if (msg.contains('confirm') || msg.contains('verified')) {
      return '이메일 인증 후 다시 로그인해 주세요';
    }
    if (msg.contains('weak')) {
      return '비밀번호가 너무 약해요';
    }
    return e.message;
  }
}
