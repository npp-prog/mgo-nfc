/// `tags/{tagId}`.
class TagInfo {
  const TagInfo({
    required this.tagId,
    required this.uid,
    required this.label,
    required this.location,
    required this.active,
    required this.url,
    this.registeredAt,
  });

  factory TagInfo.fromMap(String id, Map<String, dynamic> d) => TagInfo(
    tagId: id,
    uid: d['uid'] as String? ?? '',
    label: d['label'] as String? ?? id,
    location: d['location'] as String? ?? '',
    active: d['active'] == true,
    url: d['url'] as String? ?? '',
    registeredAt: d['registeredAt'] as DateTime?,
  );

  final String tagId;
  final String uid;
  final String label;
  final String location;
  final bool active;
  final String url;
  final DateTime? registeredAt;
}
