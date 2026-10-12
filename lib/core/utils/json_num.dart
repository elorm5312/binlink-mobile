/// Money values from the API (Prisma Decimal columns) have been sent as JSON
/// strings ("60.00") as well as numbers, so never cast them with `as num`.
double? jsonDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
