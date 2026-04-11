class HexPos {
  final int q;
  final int r;

  const HexPos(this.q, this.r);

  @override
  bool operator ==(Object other) =>
      other is HexPos && other.q == q && other.r == r;

  @override
  int get hashCode => Object.hash(q, r);

  @override
  String toString() => 'HexPos($q, $r)';

  Map<String, dynamic> toJson() => {'q': q, 'r': r};

  factory HexPos.fromJson(Map<String, dynamic> j) =>
      HexPos(j['q'] as int, j['r'] as int);
}
