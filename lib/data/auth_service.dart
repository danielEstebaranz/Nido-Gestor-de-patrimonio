import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> get userChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> register(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => _auth.signOut();
}

String authErrorMessage(Object error) {
  if (error is! FirebaseAuthException) return 'Algo ha fallado. Inténtalo de nuevo.';
  return switch (error.code) {
    'invalid-email' => 'El correo no es válido.',
    'user-disabled' => 'Esta cuenta está desactivada.',
    'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Correo o contraseña incorrectos.',
    'email-already-in-use' => 'Ya existe una cuenta con ese correo.',
    'weak-password' => 'La contraseña debe tener al menos 6 caracteres.',
    'too-many-requests' => 'Demasiados intentos. Espera un momento.',
    'network-request-failed' => 'Sin conexión. Revisa tu red.',
    'operation-not-allowed' || 'configuration-not-found' =>
      'Activa el acceso con correo y contraseña en Firebase Authentication.',
    // En Windows el SDK de C++ devuelve un error genérico tanto si la contraseña
    // es incorrecta como si Authentication no está configurado.
    'internal-error' || 'unknown' || 'unknown-error' =>
      'No se pudo iniciar sesión. Revisa el correo y la contraseña, o crea la cuenta si aún no la tienes.',
    _ => error.message ?? 'Error de autenticación (${error.code}).',
  };
}
