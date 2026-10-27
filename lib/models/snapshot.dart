import 'package:cloud_firestore/cloud_firestore.dart';

/// Foto mensual del patrimonio; el id del documento es `yyyy-MM`.
class NetWorthSnapshot {
  const NetWorthSnapshot({
    required this.id,
    required this.assetsCents,
    required this.liabilitiesCents,
  });

  factory NetWorthSnapshot.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return NetWorthSnapshot(
      id: doc.id,
      assetsCents: (d['assetsCents'] as num?)?.toInt() ?? 0,
      liabilitiesCents: (d['liabilitiesCents'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final int assetsCents;
  final int liabilitiesCents;

  int get netWorthCents => assetsCents - liabilitiesCents;

  DateTime get month {
    final parts = id.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }
}
