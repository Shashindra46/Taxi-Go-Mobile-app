class DriverModel {
  final String fullName;
  final String phone;
  final String nicNumber;
  final String userId;
  final String? email;
  final String status;

  const DriverModel({
    required this.fullName,
    required this.phone,
    required this.nicNumber,
    required this.userId,
    this.email,
    this.status = 'pending_approval',
  });

  Map<String, dynamic> toMap() => {
        'full_name': fullName,
        'phone': phone,
        'nic_number': nicNumber,
        'user_id': userId,
        if (email != null && email!.isNotEmpty) 'email': email,
        'status': status,
      };
}
