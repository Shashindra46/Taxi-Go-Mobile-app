class VehicleModel {
  final String driverId;
  final String vehicleType;
  final String brand;
  final String model;
  final String plateNumber;
  final String color;
  final int productionYear;

  const VehicleModel({
    required this.driverId,
    required this.vehicleType,
    required this.brand,
    required this.model,
    required this.plateNumber,
    required this.color,
    required this.productionYear,
  });

  Map<String, dynamic> toMap() => {
        'driver_id': driverId,
        'vehicle_type': vehicleType,
        'brand': brand,
        'model': model,
        'plate_number': plateNumber,
        'color': color,
        'production_year': productionYear,
      };
}
