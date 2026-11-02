import 'dart:convert' show utf8;
import 'dart:typed_data';

/// The UIDs of one online rule list: sorted, in typed arrays, so a few
/// million entries take ~12 bytes each and load without parsing.
///
/// A reason is stored once in [_table]; each UID keeps an index into it
/// (0 = no reason, k = `_table[k - 1]`).
class BlackMidStore {
  BlackMidStore._(this._uids, this._reasonIdx, this._table);

  static final empty = BlackMidStore._(Int64List(0), Uint32List(0), const []);

  final Int64List _uids;
  final Uint32List _reasonIdx;
  final List<String> _table;

  int get length => _uids.length;

  int _indexOf(int mid) {
    var lo = 0;
    var hi = _uids.length - 1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      final v = _uids[m];
      if (v < mid) {
        lo = m + 1;
      } else if (v > mid) {
        hi = m - 1;
      } else {
        return m;
      }
    }
    return -1;
  }

  bool contains(int mid) => _indexOf(mid) != -1;

  String? reasonOf(int mid) {
    final i = _indexOf(mid);
    if (i == -1) return null;
    final r = _reasonIdx[i];
    return r == 0 ? null : _table[r - 1];
  }

  /// Iterates all entries in UID order.
  Iterable<(int, String?)> get entries sync* {
    for (var i = 0; i < _uids.length; i++) {
      final r = _reasonIdx[i];
      yield (_uids[i], r == 0 ? null : _table[r - 1]);
    }
  }

  /// Builds a store from UIDs and their (optional) reasons.
  factory BlackMidStore.build(Set<int> mids, Map<int, String> reasons) {
    final uids = Int64List.fromList(mids.toList()..sort());
    final idx = Uint32List(uids.length);
    final table = <String>[];
    final tableIndex = <String, int>{};
    if (reasons.isNotEmpty) {
      for (var i = 0; i < uids.length; i++) {
        final reason = reasons[uids[i]];
        if (reason != null && reason.isNotEmpty) {
          idx[i] = tableIndex.putIfAbsent(reason, () {
            table.add(reason);
            return table.length;
          });
        }
      }
    }
    return BlackMidStore._(uids, idx, table);
  }

  /// A new store with [adds] (UID → reason, null for none; replaces the
  /// reason of an existing UID) and [removes] applied.
  BlackMidStore apply(Map<int, String?> adds, Set<int> removes) {
    final addKeys = adds.keys.toList()..sort();
    final out = Int64List(_uids.length + addKeys.length);
    final outIdx = Uint32List(out.length);
    final table = List<String>.of(_table);
    final tableIndex = <String, int>{
      for (var i = 0; i < table.length; i++) table[i]: i + 1,
    };
    int reasonIndex(String? reason) => reason == null || reason.isEmpty
        ? 0
        : tableIndex.putIfAbsent(reason, () {
            table.add(reason);
            return table.length;
          });

    var i = 0;
    var j = 0;
    var n = 0;
    while (i < _uids.length || j < addKeys.length) {
      final int mid;
      final int r;
      if (j >= addKeys.length || (i < _uids.length && _uids[i] < addKeys[j])) {
        mid = _uids[i];
        r = _reasonIdx[i];
        i++;
      } else {
        mid = addKeys[j];
        r = reasonIndex(adds[mid]);
        if (i < _uids.length && _uids[i] == mid) i++;
        j++;
      }
      if (removes.contains(mid)) continue;
      out[n] = mid;
      outIdx[n] = r;
      n++;
    }
    return BlackMidStore._(
      Int64List.sublistView(out, 0, n),
      Uint32List.sublistView(outIdx, 0, n),
      table,
    );
  }

  // ---- file format ----
  // header (16 bytes): 'PBMS', format 1, count, table length
  // uids: count × int64 LE, reason indices: count × uint32 LE,
  // table: per string a uint32 byte length + UTF-8 bytes

  static const _magic = 0x534D4250; // 'PBMS' little endian

  Uint8List toBytes() {
    final encoded = [for (final s in _table) utf8.encode(s)];
    final tableBytes = encoded.fold<int>(0, (a, e) => a + 4 + e.length);
    final n = _uids.length;
    final bytes = Uint8List(16 + n * 12 + tableBytes);
    final data = ByteData.sublistView(bytes)
      ..setUint32(0, _magic, Endian.little)
      ..setUint32(4, 1, Endian.little)
      ..setUint32(8, n, Endian.little)
      ..setUint32(12, _table.length, Endian.little);
    var o = 16;
    for (var i = 0; i < n; i++, o += 8) {
      data.setInt64(o, _uids[i], Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      data.setUint32(o, _reasonIdx[i], Endian.little);
    }
    for (final e in encoded) {
      data.setUint32(o, e.length, Endian.little);
      bytes.setAll(o + 4, e);
      o += 4 + e.length;
    }
    return bytes;
  }

  factory BlackMidStore.fromBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 16 ||
        data.getUint32(0, Endian.little) != _magic ||
        data.getUint32(4, Endian.little) != 1) {
      throw const FormatException('bad black mid store');
    }
    final n = data.getUint32(8, Endian.little);
    final m = data.getUint32(12, Endian.little);
    final uids = Int64List(n);
    final idx = Uint32List(n);
    var o = 16;
    for (var i = 0; i < n; i++, o += 8) {
      uids[i] = data.getInt64(o, Endian.little);
    }
    for (var i = 0; i < n; i++, o += 4) {
      idx[i] = data.getUint32(o, Endian.little);
    }
    final table = <String>[];
    for (var i = 0; i < m; i++) {
      final len = data.getUint32(o, Endian.little);
      table.add(utf8.decode(Uint8List.sublistView(bytes, o + 4, o + 4 + len)));
      o += 4 + len;
    }
    return BlackMidStore._(uids, idx, table);
  }
}
