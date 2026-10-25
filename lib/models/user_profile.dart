import 'enums.dart';

/// The signed-in user's own profile (only ever read for yourself).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.role,
    required this.companyName,
    required this.alias,
    required this.aliasCode,
    this.email,
  });

  final String id;
  final UserRole role;
  final String companyName;
  final String alias; // 'Contractor #C-4821'
  final String aliasCode; // 'C-4821'
  final String? email;

  /// '#C-4821'
  String get shortAlias => '#$aliasCode';

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        role: UserRole.fromDb(json['role'] as String?),
        companyName: json['company_name'] as String? ?? '',
        alias: json['alias'] as String? ?? '',
        aliasCode: json['alias_code'] as String? ?? '',
        email: json['email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.dbValue,
        'company_name': companyName,
        'alias': alias,
        'alias_code': aliasCode,
        'email': email,
      };

  UserProfile copyWith({String? companyName, String? email}) => UserProfile(
        id: id,
        role: role,
        companyName: companyName ?? this.companyName,
        alias: alias,
        aliasCode: aliasCode,
        email: email ?? this.email,
      );
}
