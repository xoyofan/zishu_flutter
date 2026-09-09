/// 精简 Tars(TUP)编解码:仅覆盖虎牙弹幕所需的类型子集。
/// 头字节:高 4 位 tag(15 表示扩展 1 字节 tag),低 4 位类型码。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'tars_exception.dart';

/// Tars 类型码(与标准 JCE/TUP 一致);成员名避开内建 int/double 遮蔽。
abstract final class TarsType {
  static const int int8 = 0;
  static const int int16 = 1;
  static const int int32 = 2;
  static const int int64 = 3;
  static const int float = 4;
  static const int float64 = 5;
  static const int string1 = 6;
  static const int string4 = 7;
  static const int map = 8;
  static const int list = 9;
  static const int structBegin = 10;
  static const int structEnd = 11;
  static const int zeroTag = 12;
  static const int simpleList = 13;
}

class _Head {
  int type = 0;
  int tag = 0;
}

class TarsWriter {
  final _buffer = BytesBuilder(copy: false);

  int get length => _buffer.length;

  Uint8List takeBytes() => _buffer.takeBytes();

  void _writeRaw(int value, int size) {
    final data = ByteData(size);
    switch (size) {
      case 1:
        data.setUint8(0, value & 0xff);
      case 2:
        data.setInt16(0, value, Endian.big);
      case 4:
        data.setInt32(0, value, Endian.big);
      case 8:
        data.setInt64(0, value, Endian.big);
      default:
        throw TarsEncodeException('invalid size: $size');
    }
    _buffer.add(data.buffer.asUint8List());
  }

  void _writeHead(int type, int tag) {
    if (tag < 15) {
      _writeRaw((tag << 4) | type, 1);
    } else if (tag < 256) {
      _writeRaw((15 << 4) | type, 1);
      _writeRaw(tag, 1);
    } else {
      throw TarsEncodeException('tag too large: $tag');
    }
  }

  void writeInt(int value, int tag) {
    if (value >= -128 && value <= 127) {
      if (value == 0) {
        _writeHead(TarsType.zeroTag, tag);
      } else {
        _writeHead(TarsType.int8, tag);
        _writeRaw(value, 1);
      }
      return;
    }
    if (value >= -32768 && value <= 32767) {
      _writeHead(TarsType.int16, tag);
      _writeRaw(value, 2);
      return;
    }
    if (value >= -2147483648 && value <= 2147483647) {
      _writeHead(TarsType.int32, tag);
      _writeRaw(value, 4);
      return;
    }
    _writeHead(TarsType.int64, tag);
    _writeRaw(value, 8);
  }

  void writeBool(bool value, int tag) => writeInt(value ? 1 : 0, tag);

  void writeString(String value, int tag) {
    final bytes = utf8.encode(value);
    if (bytes.length > 255) {
      _writeHead(TarsType.string4, tag);
      _writeRaw(bytes.length, 4);
    } else {
      _writeHead(TarsType.string1, tag);
      _writeRaw(bytes.length, 1);
    }
    _buffer.add(bytes);
  }

  /// byte 数组:SimpleList(头 + 元素类型 byte + 长度 + 数据)。
  void writeBytes(Uint8List value, int tag) {
    _writeHead(TarsType.simpleList, tag);
    _writeHead(TarsType.int8, 0);
    writeInt(value.length, 0);
    _buffer.add(value);
  }

  /// 字符串列表。
  void writeStringList(List<String> value, int tag) {
    _writeHead(TarsType.list, tag);
    writeInt(value.length, 0);
    for (final item in value) {
      writeString(item, 0);
    }
  }

  /// 自定义结构:STRUCT_BEGIN + 字段 + STRUCT_END。
  void writeStruct(void Function(TarsWriter) writeFields, int tag) {
    _writeHead(TarsType.structBegin, tag);
    writeFields(this);
    _writeHead(TarsType.structEnd, 0);
  }
}

class TarsReader {
  TarsReader(this._data, {this.position = 0});

  final Uint8List _data;
  int position;

  int get remaining => _data.length - position;

  int _readRaw(int size) {
    if (position + size > _data.length) {
      throw const TarsDecodeException('unexpected end of stream');
    }
    final view = ByteData.sublistView(_data, position, position + size);
    position += size;
    switch (size) {
      case 1:
        return view.getInt8(0);
      case 2:
        return view.getInt16(0, Endian.big);
      case 4:
        return view.getInt32(0, Endian.big);
      case 8:
        return view.getInt64(0, Endian.big);
      default:
        throw TarsDecodeException('invalid size: $size');
    }
  }

  _Head _readHead() {
    final head = _Head();
    if (position >= _data.length) {
      throw const TarsDecodeException('unexpected end of stream');
    }
    final b = _readRaw(1);
    head.type = b & 0x0f;
    head.tag = (b & 0xf0) >> 4;
    if (head.tag == 15) {
      head.tag = _readRaw(1);
    }
    return head;
  }

  int _peekHead(_Head head) {
    final current = position;
    final peeked = _readHead();
    final consumed = position - current;
    position = current;
    head.tag = peeked.tag;
    head.type = peeked.type;
    return consumed;
  }

  void _skipField(int type) {
    switch (type) {
      case TarsType.int8:
        position += 1;
      case TarsType.int16:
        position += 2;
      case TarsType.int32:
        position += 4;
      case TarsType.int64:
        position += 8;
      case TarsType.float:
        position += 4;
      case TarsType.float64:
        position += 8;
      case TarsType.string1:
        var len = _readRaw(1);
        if (len < 0) len += 256;
        position += len;
      case TarsType.string4:
        position += _readRaw(4);
      case TarsType.map:
        final size = readInt(0);
        for (var i = 0; i < size * 2; i++) {
          _skipFieldHead();
        }
      case TarsType.list:
        final size = readInt(0);
        for (var i = 0; i < size; i++) {
          _skipFieldHead();
        }
      case TarsType.simpleList:
        final head = _readHead();
        if (head.type != TarsType.int8) {
          throw TarsDecodeException('invalid simple list element type: ${head.type}');
        }
        final size = readInt(0);
        position += size;
      case TarsType.structBegin:
        _skipToStructEnd();
      case TarsType.structEnd:
      case TarsType.zeroTag:
        break;
      default:
        throw TarsDecodeException('unknown field type: $type');
    }
  }

  void _skipFieldHead() {
    final head = _readHead();
    _skipField(head.type);
  }

  void _skipToStructEnd() {
    do {
      final head = _readHead();
      if (head.type == TarsType.structEnd) return;
      _skipField(head.type);
    } while (true);
  }

  bool _skipToTag(int tag) {
    final head = _Head();
    while (true) {
      final int consumed;
      try {
        consumed = _peekHead(head);
      } on TarsDecodeException {
        // 流提前耗尽:目标字段不存在。
        return false;
      }
      if (tag <= head.tag || head.type == TarsType.structEnd) {
        return tag == head.tag;
      }
      position += consumed;
      _skipField(head.type);
    }
  }

  int _intFromType(int type) {
    switch (type) {
      case TarsType.zeroTag:
        return 0;
      case TarsType.int8:
      case TarsType.int16:
      case TarsType.int32:
      case TarsType.int64:
        final size = switch (type) {
          TarsType.int8 => 1,
          TarsType.int16 => 2,
          TarsType.int32 => 4,
          _ => 8,
        };
        return _readRaw(size);
      default:
        throw TarsDecodeException('type mismatch for int: $type');
    }
  }

  /// 读整数字段;字段缺失返回 [fallback]。
  int readInt(int tag, {int fallback = 0}) {
    if (_skipToTag(tag)) {
      final head = _readHead();
      return _intFromType(head.type);
    }
    return fallback;
  }

  bool readBool(int tag, {bool fallback = false}) =>
      readInt(tag, fallback: fallback ? 1 : 0) != 0;

  String readString(int tag, {String fallback = ''}) {
    if (_skipToTag(tag)) {
      final head = _readHead();
      final int len;
      switch (head.type) {
        case TarsType.string1:
          len = _readRaw(1);
        case TarsType.string4:
          len = _readRaw(4);
        default:
          throw TarsDecodeException('type mismatch for string: ${head.type}');
      }
      if (len < 0 || position + len > _data.length) {
        throw TarsDecodeException('string length out of range: $len');
      }
      final result = utf8.decode(_data.sublist(position, position + len), allowMalformed: true);
      position += len;
      return result;
    }
    return fallback;
  }

  Uint8List readBytes(int tag) {
    if (_skipToTag(tag)) {
      final head = _readHead();
      if (head.type != TarsType.simpleList) {
        throw TarsDecodeException('type mismatch for bytes: ${head.type}');
      }
      final element = _readHead();
      if (element.type != TarsType.int8) {
        throw TarsDecodeException('invalid simple list element type: ${element.type}');
      }
      final size = readInt(0);
      final result = Uint8List.sublistView(_data, position, position + size);
      position += size;
      return result;
    }
    return Uint8List(0);
  }

  List<String> readStringList(int tag) {
    final result = <String>[];
    if (_skipToTag(tag)) {
      final head = _readHead();
      if (head.type != TarsType.list) {
        throw TarsDecodeException('type mismatch for list: ${head.type}');
      }
      final size = readInt(0);
      for (var i = 0; i < size; i++) {
        result.add(readString(0));
      }
    }
    return result;
  }

  /// 读自定义结构字段;字段缺失时不调用 [readFields]。
  void readStruct(int tag, void Function(TarsReader) readFields) {
    if (_skipToTag(tag)) {
      final head = _readHead();
      if (head.type != TarsType.structBegin) {
        throw TarsDecodeException('type mismatch for struct: ${head.type}');
      }
      readFields(this);
      _skipToStructEnd();
    }
  }

  /// 读结构列表字段;元素缺失时返回空列表。
  List<T> readStructList<T>(
    int tag,
    T Function(TarsReader) createElement,
  ) {
    final result = <T>[];
    if (_skipToTag(tag)) {
      final head = _readHead();
      if (head.type != TarsType.list) {
        throw TarsDecodeException('type mismatch for struct list: ${head.type}');
      }
      final size = readInt(0);
      for (var i = 0; i < size; i++) {
        final elementHead = _readHead();
        if (elementHead.type != TarsType.structBegin) {
          throw TarsDecodeException('list element is not a struct: ${elementHead.type}');
        }
        result.add(createElement(this));
        _skipToStructEnd();
      }
    }
    return result;
  }
}

/// 解析整帧:返回 WebSocketCommand 的 cmdType 与 data。
({int cmdType, Uint8List data}) decodeTarsCommandFrame(Uint8List frame) {
  final reader = TarsReader(frame);
  final cmdType = reader.readInt(0);
  final data = reader.readBytes(1);
  return (cmdType: cmdType, data: data);
}
