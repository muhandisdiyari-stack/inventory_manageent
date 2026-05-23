part of 'auth_bloc.dart';

enum AuthStatus {
  unknown,
  initializing,
  unauthenticated,
  authenticating,
  authenticated,
  emailUnconfirmed,
  emailConfirmed,
  error,
}

class AuthState {
  final AuthStatus status;
  final User? user;
  final String? error;
  final String? pendingEmail;
  final bool isAdmin;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
    this.pendingEmail,
    this.isAdmin = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? error,
    String? pendingEmail,
    bool? isAdmin,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
      pendingEmail: pendingEmail ?? this.pendingEmail,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get needsEmailConfirmation => status == AuthStatus.emailUnconfirmed;
}