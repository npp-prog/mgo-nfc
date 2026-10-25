enum UserRole {
  employee,
  admin;

  static UserRole parse(Object? value) =>
      value == 'admin' ? UserRole.admin : UserRole.employee;
}

/// Profile from `users/{uid}`. Timestamps must already be converted to
/// [DateTime] (see `firestoreToPlain`).
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.employeeId,
    required this.role,
    required this.active,
    this.trackAttendance = true,
    this.createdAt,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) => AppUser(
    uid: uid,
    email: data['email'] as String? ?? '',
    displayName: data['displayName'] as String? ?? '',
    employeeId: data['employeeId'] as String? ?? '',
    role: UserRole.parse(data['role']),
    active: data['active'] == true,
    trackAttendance: data['trackAttendance'] != false,
    createdAt: data['createdAt'] as DateTime?,
  );

  final String uid;
  final String email;
  final String displayName;
  final String employeeId;
  final UserRole role;
  final bool active;

  /// When false the user is left out of absence counts (e.g. owners, remote staff).
  final bool trackAttendance;
  final DateTime? createdAt;

  bool get isAdmin => role == UserRole.admin;

  String get name => displayName.isNotEmpty ? displayName : email;
}
