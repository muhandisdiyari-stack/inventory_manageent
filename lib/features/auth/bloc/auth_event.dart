part of 'auth_bloc.dart';

sealed class AuthEvent {
  const AuthEvent();
}

class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

class SignInRequested extends AuthEvent {
  final String email;
  final String password;
  const SignInRequested({required this.email, required this.password});
}

class SignUpRequested extends AuthEvent {
  final String email;
  final String password;
  final String displayName;
  const SignUpRequested({
    required this.email,
    required this.password,
    required this.displayName,
  });
}

class SignOutRequested extends AuthEvent {
  const SignOutRequested();
}

class EmailConfirmationReceived extends AuthEvent {
  const EmailConfirmationReceived();
}

class AdminCheckRequested extends AuthEvent {
  const AdminCheckRequested();
}

class DeepLinkReceived extends AuthEvent {
  final Uri uri;
  const DeepLinkReceived(this.uri);
}

class ClearAuthError extends AuthEvent {
  const ClearAuthError();
}