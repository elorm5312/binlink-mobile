import 'package:binlink_mobile/core/utils/json_num.dart';

class UserModel {
  final String id;
  final String? phone;
  final String? email;
  final String role; // HOUSEHOLD | COLLECTOR | ADMIN
  final String? fullName;
  final String? address;
  final String? profilePhoto;
  final String status; // PENDING | ACTIVE | SUSPENDED
  final bool isOnline;
  final double rating;
  final double totalEarned;
  final int totalPickups;
  final String? vehicleType;
  final String? vehiclePlate;
  final double? lastLat;
  final double? lastLng;
  final String? memberSince;
  final int ecoPoints;
  final double totalKgRecycled;
  final double currentLoadKg;
  final double maxCapacityKg;

  const UserModel({
    required this.id,
    required this.role,
    this.phone,
    this.email,
    this.fullName,
    this.address,
    this.profilePhoto,
    this.status = 'ACTIVE',
    this.isOnline = false,
    this.rating = 5.0,
    this.totalEarned = 0.0,
    this.totalPickups = 0,
    this.vehicleType,
    this.vehiclePlate,
    this.lastLat,
    this.lastLng,
    this.memberSince,
    this.ecoPoints = 0,
    this.totalKgRecycled = 0.0,
    this.currentLoadKg = 0.0,
    this.maxCapacityKg = 500.0,
  });

  bool get isHousehold => role == 'HOUSEHOLD';
  bool get isCollector => role == 'COLLECTOR';
  bool get isAdmin => role == 'ADMIN';
  bool get isPending => status == 'PENDING';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id:           json['id'] as String,
      phone:        json['phone'] as String?,
      email:        json['email'] as String?,
      role:         json['role'] as String? ?? 'HOUSEHOLD',
      fullName:     json['fullName'] as String?,
      address:      json['address'] as String?,
      profilePhoto: json['profilePhoto'] as String?,
      status:       json['status'] as String? ?? 'ACTIVE',
      isOnline:     json['isOnline'] as bool? ?? false,
      rating:       jsonDouble(json['rating']) ?? 5.0,
      totalEarned:  jsonDouble(json['totalEarned']) ?? 0.0,
      totalPickups: json['totalPickups'] as int? ?? 0,
      vehicleType:      json['vehicleType'] as String?,
      vehiclePlate:     json['vehiclePlate'] as String?,
      lastLat:          jsonDouble(json['lastLat']),
      lastLng:          jsonDouble(json['lastLng']),
      memberSince:      json['createdAt'] as String?,
      ecoPoints:        json['ecoPoints'] as int? ?? 0,
      totalKgRecycled:  jsonDouble(json['totalKgRecycled']) ?? 0.0,
      currentLoadKg:    jsonDouble(json['currentLoadKg']) ?? 0.0,
      maxCapacityKg:    jsonDouble(json['maxCapacityKg']) ?? 500.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'phone': phone, 'email': email, 'role': role,
    'fullName': fullName, 'address': address, 'profilePhoto': profilePhoto, 'status': status,
    'isOnline': isOnline, 'rating': rating, 'totalEarned': totalEarned, 'totalPickups': totalPickups,
    'vehicleType': vehicleType, 'vehiclePlate': vehiclePlate,
    'lastLat': lastLat, 'lastLng': lastLng,
  };

  UserModel copyWith({
    String? phone, String? email, String? fullName, String? address, String? profilePhoto,
    bool? isOnline, double? rating, double? totalEarned, int? totalPickups,
    String? vehicleType, String? vehiclePlate,
    double? lastLat, double? lastLng,
    double? currentLoadKg, double? maxCapacityKg,
    int? ecoPoints, double? totalKgRecycled,
  }) {
    return UserModel(
      id: id, role: role, status: status,
      memberSince: memberSince,
      phone:          phone          ?? this.phone,
      email:          email          ?? this.email,
      fullName:       fullName       ?? this.fullName,
      address:        address        ?? this.address,
      profilePhoto:   profilePhoto   ?? this.profilePhoto,
      isOnline:       isOnline       ?? this.isOnline,
      rating:         rating         ?? this.rating,
      totalEarned:    totalEarned    ?? this.totalEarned,
      totalPickups:   totalPickups   ?? this.totalPickups,
      vehicleType:    vehicleType    ?? this.vehicleType,
      vehiclePlate:   vehiclePlate   ?? this.vehiclePlate,
      lastLat:        lastLat        ?? this.lastLat,
      lastLng:        lastLng        ?? this.lastLng,
      currentLoadKg:  currentLoadKg  ?? this.currentLoadKg,
      maxCapacityKg:  maxCapacityKg  ?? this.maxCapacityKg,
      ecoPoints:      ecoPoints      ?? this.ecoPoints,
      totalKgRecycled: totalKgRecycled ?? this.totalKgRecycled,
    );
  }
}
