import 'package:cloud_firestore/cloud_firestore.dart';

/// Copies a Firestore document map, turning [Timestamp]s into [DateTime]s so
/// models don't depend on the Firestore SDK.
Map<String, dynamic> firestoreToPlain(Map<String, dynamic> data) => {
  for (final e in data.entries)
    e.key: e.value is Timestamp ? (e.value as Timestamp).toDate() : e.value,
};
