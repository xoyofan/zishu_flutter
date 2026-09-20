/// WASAPI loopback 音频采集(Windows,dart:ffi 直调 COM)。
///
/// 两种模式(实现 [AudioTapSource],交错 float32 输出):
/// - 进程 loopback(默认):经 `ActivateAudioInterfaceAsync` 的
///   VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK 只捕获本进程树播放的音频,
///   不混入其他应用声音(Win10 2004+)。
/// - 系统输出 loopback:捕获默认渲染设备全部输出(会混入其他应用声音)。
///
/// 采集循环 = 本 isolate 20ms Timer 轮询 GetNextPacketSize/GetBuffer,
/// WASAPI 侧 100ms 缓冲积累数据,轮询抖动不丢帧;相比独立采集 isolate,
/// 销毁路径干净且免去跨 isolate 拷贝。
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:speech2zh/speech2zh.dart';

// ---------------------------------------------------------------------------
// FFI 结构与常量
// ---------------------------------------------------------------------------

final class Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;

  /// 解析 'XXXXXXXX-xxxx-xxxx-xxxx-xxxxxxxxxxxx' 为 malloc 分配的 GUID。
  static Pointer<Guid> alloc(String s) {
    final hex = s.replaceAll('-', '');
    final g = malloc<Guid>();
    g.ref
      ..data1 = int.parse(hex.substring(0, 8), radix: 16)
      ..data2 = int.parse(hex.substring(8, 12), radix: 16)
      ..data3 = int.parse(hex.substring(12, 16), radix: 16);
    for (var i = 0; i < 8; i++) {
      g.ref.data4[i] =
          int.parse(hex.substring(16 + i * 2, 18 + i * 2), radix: 16);
    }
    return g;
  }
}

/// WAVEFORMATEXTENSIBLE(自然布局 40 字节,x64)。
final class WaveFormatEx extends Struct {
  @Uint16()
  external int formatTag;
  @Uint16()
  external int channels;
  @Uint32()
  external int samplesPerSec;
  @Uint32()
  external int avgBytesPerSec;
  @Uint16()
  external int blockAlign;
  @Uint16()
  external int bitsPerSample;
  @Uint16()
  external int cbSize;
  // EXTENSIBLE 扩展(cbSize=22):
  @Uint16()
  external int validBits;
  @Uint32()
  external int channelMask;
  external Guid subFormat;
}

/// x64 布局:type@0 + union{DWORD ProcessId, enum Mode}@4。
final class AudioClientActivationParams extends Struct {
  @Int32()
  external int activationType;
  @Uint32()
  external int targetProcessId;
  @Int32()
  external int processLoopbackMode;
}

/// PROPVARIANT,仅覆盖 VT_BLOB/VT_UNKNOWN(x64 24 字节)。
final class PropVariant extends Struct {
  @Uint16()
  external int vt;
  @Uint16()
  external int r1;
  @Uint16()
  external int r2;
  @Uint16()
  external int r3;
  // union 起始(x64 对齐到 8):BLOB = {ULONG cbSize; BYTE* pBlobData},
  // UNKNOWN = {IUnknown* punkVal} —— 二者指针位同为偏移 16。
  @Uint32()
  external int blobSize;
  external Pointer<Uint8> blobData;
}

// COM vtable:对象首字段 = vtable 指针,槽位从 0 起。
Pointer<NativeFunction<F>> _slot<F extends Function>(
    Pointer<Uint8> obj, int index) {
  final vtable = Pointer.fromAddress(obj.cast<IntPtr>().value);
  return vtable.cast<Pointer<NativeFunction<F>>>()[index];
}

typedef _Fn1 = Int32 Function(Pointer);
typedef _Fn1D = int Function(Pointer);
typedef _Fn2p = Int32 Function(Pointer, Pointer);
typedef _Fn2pD = int Function(Pointer, Pointer);
typedef _Fn2u = Int32 Function(Pointer, Uint32);
typedef _Fn2uD = int Function(Pointer, int);
typedef _VFn2p = Void Function(Pointer, Pointer);
typedef _Fn3 = Int32 Function(Pointer, Pointer, Pointer);
typedef _Fn3D = int Function(Pointer, Pointer, Pointer);
typedef _Fn4 = Int32 Function(Pointer, Uint32, Uint32, Pointer);
typedef _Fn4D = int Function(Pointer, int, int, Pointer);
typedef _Fn5 = Int32 Function(Pointer, Pointer, Uint32, Pointer, Pointer);
typedef _Fn5D = int Function(Pointer, Pointer, int, Pointer, Pointer);
typedef _Fn7 = Int32 Function(Pointer, Uint32, Uint32, Uint64, Uint64,
    Pointer, Pointer);
typedef _Fn7D = int Function(Pointer, int, int, int, int, Pointer, Pointer);
typedef _Fn6 = Int32 Function(
    Pointer, Pointer, Pointer, Pointer, Pointer, Pointer);
typedef _Fn6D = int Function(
    Pointer, Pointer, Pointer, Pointer, Pointer, Pointer);

int _release(Pointer<Uint8> obj) => _slot<_Fn1>(obj, 2).asFunction<_Fn1D>()(obj);

const _clsctxAll = 1;
const _eNoInterface = 0x80004002;
const _audclntShared = 0;
const _flagLoopback = 0x00020000;
const _flagAutoConvertPcm = 0x80000000;
const _flagSrcDefaultQuality = 0x08000000;
const _bufferFlagsSilent = 2;
const _vtBlob = 65;
const _activationTypeProcessLoopback = 1;
const _loopbackIncludeTargetTree = 1;

final _clsidMmDeviceEnumerator =
    Guid.alloc('BCDE0395-E52F-467C-8E3D-C4579291692E');
final _iidMmDeviceEnumerator =
    Guid.alloc('A95664D2-9614-4F35-A746-DE8DB63617E6');
final _iidAudioClient = Guid.alloc('1CB9AD4C-DBFA-4C32-B178-C2F568A703B2');
final _iidAudioCaptureClient =
    Guid.alloc('C8ADBD64-E71E-48A0-A4DE-185C395CD317');
final _subformatIeeeFloat =
    Guid.alloc('00000003-0000-0010-8000-00AA00389B71');
typedef _ActivateAudioInterfaceNative = Int32 Function(
    Pointer, Pointer, Pointer, Pointer, Pointer);
typedef _ActivateFnDart = int Function(
    Pointer, Pointer, Pointer, Pointer, Pointer);

_ActivateFnDart _activateFn() {
  final lib = DynamicLibrary.open('mmdevapi.dll');
  return lib
      .lookup<NativeFunction<_ActivateAudioInterfaceNative>>(
          'ActivateAudioInterfaceAsync')
      .asFunction<_ActivateFnDart>();
}

// ---------------------------------------------------------------------------
// IActivateAudioInterfaceCompletionHandler(自定义 COM 对象)
// ---------------------------------------------------------------------------

class _CompletionHandler {
  _CompletionHandler(this.onCompleted) {
    _completed = NativeCallable<_VFn2p>.listener((Pointer self, Pointer worker) {
      onCompleted(worker.cast<Uint8>());
    });
    final vtable = malloc<Pointer<Void>>(4);
    vtable[0] =
        Pointer.fromFunction<_Fn3>(_qiAgile, _eNoInterface).cast<Void>();
    vtable[1] = Pointer.fromFunction<_Fn1>(_retOne, 1).cast<Void>();
    vtable[2] = Pointer.fromFunction<_Fn1>(_retOne, 1).cast<Void>();
    vtable[3] = _completed!.nativeFunction.cast<Void>();
    _vtable = vtable;
    object = malloc<Uint8>(sizeOf<IntPtr>());
    object.cast<IntPtr>().value = vtable.address;
  }

  final void Function(Pointer<Uint8> worker) onCompleted;

  NativeCallable<_VFn2p>? _completed;
  Pointer<Pointer<Void>>? _vtable;
  late final Pointer<Uint8> object;

  void dispose() {
    _completed?.close();
    _completed = null;
    if (_vtable != null) {
      malloc.free(_vtable!);
      _vtable = null;
    }
    malloc.free(object);
  }
}

int _retOne(Pointer self) => 1;

int _qiAgile(Pointer self, Pointer riid, Pointer ppv) {
  final iid = riid.cast<Guid>().ref;
  final out = ppv.cast<Pointer<Uint8>>();
  // IUnknown 或 IAgileObject(ActivateAudioInterfaceAsync 的 handler 需为
  // agile 对象,否则激活失败)。
  final isIUnknown = iid.data1 == 0 &&
      iid.data2 == 0 &&
      iid.data3 == 0 &&
      iid.data4[0] == 0xC0 &&
      iid.data4[7] == 0x46;
  final isAgile = iid.data1 == 0x94EA2B94 &&
      iid.data2 == 0xE9CC &&
      iid.data3 == 0x49E0 &&
      iid.data4[0] == 0xC0 &&
      iid.data4[1] == 0xFF &&
      iid.data4[2] == 0xEE &&
      iid.data4[3] == 0x3C &&
      iid.data4[4] == 0xC5 &&
      iid.data4[5] == 0xA5 &&
      iid.data4[6] == 0x7C &&
      iid.data4[7] == 0x8F;
  // IActivateAudioInterfaceCompletionHandler 自身:系统在激活时 QI 校验
  // handler 类型,缺失会返回"意外时机"错误(0x8000000E)。
  final isCompletionHandler = iid.data1 == 0x94EA2B8E &&
      iid.data2 == 0x1FB6 &&
      iid.data3 == 0x4A05 &&
      iid.data4[0] == 0x83 &&
      iid.data4[1] == 0x41 &&
      iid.data4[2] == 0xE4 &&
      iid.data4[3] == 0xD0 &&
      iid.data4[4] == 0x70 &&
      iid.data4[5] == 0x3B &&
      iid.data4[6] == 0xA0 &&
      iid.data4[7] == 0x64;
  // IID_IMarshal(00000003-0000-0000-C000-000000000046):真 agile 需要
  // free-threaded marshaler,返回 FTM 的未知接口由系统调其 IMarshal。
  final isMarshal = iid.data1 == 0x00000003 &&
      iid.data2 == 0x0000 &&
      iid.data3 == 0x0000 &&
      iid.data4[0] == 0xC0 &&
      iid.data4[7] == 0x46;
  if (isIUnknown || isAgile || isCompletionHandler) {
    out.value = self.cast<Uint8>();
    return 0;
  }
  if (isMarshal) {
    final ftm = _freeThreadedMarshaler();
    if (ftm != null) {
      out.value = ftm;
      return 0;
    }
  }
  out.value = nullptr;
  return _eNoInterface;
}

Pointer<Uint8>? _ftmCache;

Pointer<Uint8>? _freeThreadedMarshaler() {
  if (_ftmCache != null) return _ftmCache;
  final ole32 = DynamicLibrary.open('ole32.dll');
  final create = ole32
      .lookup<
          NativeFunction<
              Int32 Function(Pointer, Pointer)>>('CoCreateFreeThreadedMarshaler')
      .asFunction<int Function(Pointer, Pointer)>();
  final out = malloc<Pointer<Uint8>>();
  final hr = create(nullptr, out);
  if (hr != 0) {
    malloc.free(out);
    return null;
  }
  return _ftmCache = out.value;
}

// ---------------------------------------------------------------------------
// WasapiLoopbackTap
// ---------------------------------------------------------------------------

class WasapiLoopbackTap implements AudioTapSource {
  WasapiLoopbackTap({
    this.captureSystemOutput = false,
    this.targetSampleRate = 48000,
    this.targetChannels = 2,
  });

  /// true = 系统默认输出 loopback(混入其他应用);false = 本进程 loopback。
  final bool captureSystemOutput;
  final int targetSampleRate;
  final int targetChannels;

  @override
  int get sampleRate => targetSampleRate;

  @override
  int get channels => targetChannels;

  final _pcmCtl = StreamController<Float32List>.broadcast();
  Timer? _poll;
  Pointer<Uint8>? _client;
  Pointer<Uint8>? _capture;
  _CompletionHandler? _handler;

  /// 进程 loopback 激活失败后是否已自动降级(记录一次,供 UI/日志提示)。
  static bool degradedToSystemOutput = false;

  @override
  Stream<Float32List> get pcm => _pcmCtl.stream;

  @override
  Future<void> start() async {
    _coInit();
    Pointer<Uint8> client;
    if (captureSystemOutput) {
      client = _activateSystemDevice();
    } else {
      try {
        client = await _activateProcessLoopback();
      } catch (e) {
        // 进程 loopback 依赖 STA/消息泵语境;CLI 或非常规线程可能激活失败
        // (E_ILLEGAL_METHOD_CALL)。降级为系统输出 loopback,功能仍可用,
        // 只是会混入其他应用声音。Flutter app 主线程(STA+泵)预期不会走到。
        degradedToSystemOutput = true;
        // ignore: avoid_print
        print('speech_tap: process loopback failed ($e); fallback to system output');
        client = _activateSystemDevice();
      }
    }
    final wfx = _makeFormat();
    final initialize =
        _slot<_Fn7>(client, 3).asFunction<_Fn7D>();
    final hr = initialize(
      client,
      _audclntShared,
      _flagLoopback | _flagAutoConvertPcm | _flagSrcDefaultQuality,
      1000000, // 100ms 缓冲,给 20ms 轮询留余量
      0,
      wfx,
      nullptr,
    );
    malloc.free(wfx);
    if (hr != 0) {
      _release(client);
      throw StateError('IAudioClient.Initialize hr=0x${(hr & 0xFFFFFFFF).toRadixString(16).padLeft(8, "0")}');
    }
    _client = client;

    final getService = _slot<_Fn3>(client, 14).asFunction<_Fn3D>();
    final capOut = malloc<Pointer<Uint8>>();
    final hs = getService(client, _iidAudioCaptureClient, capOut);
    if (hs != 0) {
      malloc.free(capOut);
      _release(client);
      _client = null;
      throw StateError('GetService(Capture) hr=0x${hs.toRadixString(16)}');
    }
    _capture = capOut.value;
    malloc.free(capOut);

    final startFn = _slot<_Fn1>(client, 10).asFunction<_Fn1D>();
    final hs2 = startFn(client);
    if (hs2 != 0) {
      throw StateError('IAudioClient.Start hr=0x${hs2.toRadixString(16)}');
    }
    _poll = Timer.periodic(const Duration(milliseconds: 20), (_) => _drain());
  }

  void _drain() {
    final capture = _capture;
    if (capture == null || _pcmCtl.isClosed) return;
    final nextSize = _slot<_Fn2p>(capture, 5).asFunction<_Fn2pD>();
    final getBuffer = _slot<_Fn6>(capture, 3).asFunction<_Fn6D>();
    final releaseBuffer = _slot<_Fn2u>(capture, 4).asFunction<_Fn2uD>();
    final framesOut = malloc<Uint32>();
    final flagsOut = malloc<Uint32>();
    final dataOut = malloc<Pointer<Uint8>>();
    try {
      while (!_pcmCtl.isClosed) {
        if (nextSize(capture, framesOut) != 0) return;
        final frames = framesOut.value;
        if (frames == 0) return;
        final hr = getBuffer(
            capture, dataOut, framesOut, flagsOut, nullptr, nullptr);
        if (hr != 0) return;
        final silent = (flagsOut.value & _bufferFlagsSilent) != 0;
        final sampleCount = frames * targetChannels;
        final list = Float32List(sampleCount);
        if (!silent) {
          list.setAll(0, dataOut.value.cast<Float>().asTypedList(sampleCount));
        }
        releaseBuffer(capture, frames);
        _pcmCtl.add(list);
      }
    } finally {
      malloc.free(framesOut);
      malloc.free(flagsOut);
      malloc.free(dataOut);
    }
  }

  @override
  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    final client = _client;
    if (client != null) {
      _slot<_Fn1>(client, 11).asFunction<_Fn1D>()(client); // Stop
    }
    if (_capture != null) {
      _release(_capture!);
      _capture = null;
    }
    if (client != null) {
      _release(client);
      _client = null;
    }
    _handler?.dispose();
    _handler = null;
    if (!_pcmCtl.isClosed) {
      await _pcmCtl.close();
    }
  }

  int _coInit() {
    final ole32 = DynamicLibrary.open('ole32.dll');
    final coInit = ole32
        .lookup<NativeFunction<Int32 Function(Pointer, Uint32)>>('CoInitializeEx')
        .asFunction<int Function(Pointer, int)>();
    // COINIT_MULTITHREADED | COINIT_DISABLE_OLE1DDE;若进程已按 STA 初始化
    // (RPC_E_CHANGED_MODE)则容忍,后续 COM 调用依旧成立。
    return coInit(nullptr, 0x0 | 0x4);
  }

  Pointer<Uint8> _activateSystemDevice() {
    final ole32 = DynamicLibrary.open('ole32.dll');
    final coCreate = ole32
        .lookup<NativeFunction<_Fn5>>('CoCreateInstance')
        .asFunction<_Fn5D>();
    final enumOut = malloc<Pointer<Uint8>>();
    var hr = coCreate(_clsidMmDeviceEnumerator, nullptr, _clsctxAll,
        _iidMmDeviceEnumerator, enumOut);
    if (hr != 0) {
      malloc.free(enumOut);
      throw StateError('CoCreateInstance hr=0x${(hr & 0xFFFFFFFF).toRadixString(16).padLeft(8, "0")}');
    }
    final enumerator = enumOut.value;
    malloc.free(enumOut);

    final getDefault = _slot<_Fn4>(enumerator, 4).asFunction<_Fn4D>();
    final devOut = malloc<Pointer<Uint8>>();
    hr = getDefault(enumerator, 0, 0, devOut); // eRender, eConsole
    _release(enumerator);
    if (hr != 0) {
      malloc.free(devOut);
      throw StateError('GetDefaultAudioEndpoint hr=0x${(hr & 0xFFFFFFFF).toRadixString(16).padLeft(8, "0")}');
    }
    final device = devOut.value;
    malloc.free(devOut);

    final activate = _slot<_Fn5>(device, 3).asFunction<_Fn5D>();
    final clientOut = malloc<Pointer<Uint8>>();
    hr = activate(
        device, _iidAudioClient, _clsctxAll, nullptr, clientOut);
    _release(device);
    if (hr != 0) {
      malloc.free(clientOut);
      throw StateError('IMMDevice.Activate hr=0x${(hr & 0xFFFFFFFF).toRadixString(16).padLeft(8, "0")}');
    }
    final client = clientOut.value;
    malloc.free(clientOut);
    return client;
  }

  Future<Pointer<Uint8>> _activateProcessLoopback() {
    final completer = Completer<Pointer<Uint8>>();
    final params = malloc<AudioClientActivationParams>();
    params.ref
      ..activationType = _activationTypeProcessLoopback
      ..targetProcessId = 0 // 0 = 调用进程整棵树
      ..processLoopbackMode = _loopbackIncludeTargetTree;

    final pv = malloc<PropVariant>();
    pv.ref
      ..vt = _vtBlob
      ..r1 = 0
      ..r2 = 0
      ..r3 = 0
      ..blobSize = sizeOf<AudioClientActivationParams>()
      ..blobData = params.cast<Uint8>();

    final handler = _CompletionHandler((worker) {
      try {
        final getResults = _slot<_Fn3>(worker, 3).asFunction<_Fn3D>();
        final handlerOut = malloc<Pointer<Uint8>>();
        final resultPv = malloc<PropVariant>();
        final hr = getResults(worker, handlerOut, resultPv);
        malloc.free(handlerOut);
        // VT_UNKNOWN 的对象指针位于 PROPVARIANT union 首槽(x64 偏移 8)。
        final clientAddr = (resultPv.cast<IntPtr>() + 1).value;
        malloc.free(resultPv);
        _release(worker);
        if (!completer.isCompleted) {
          if (hr == 0 && clientAddr != 0) {
            completer.complete(Pointer<Uint8>.fromAddress(clientAddr));
          } else {
            completer.completeError(
                StateError('activation GetResults hr=0x${(hr & 0xFFFFFFFF).toRadixString(16).padLeft(8, "0")}'));
          }
        }
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
    _handler = handler;

    final workerOut = malloc<Pointer<Uint8>>();
    final hr = _activateFn()(
      _virtualDeviceName(),
      _iidAudioClient,
      pv,
      handler.object,
      workerOut,
    );
    malloc.free(pv);
    malloc.free(params);
    malloc.free(workerOut);
    if (hr != 0) {
      handler.dispose();
      _handler = null;
      return Future.error(
          StateError('ActivateAudioInterfaceAsync hr=0x${(hr & 0xFFFFFFFF).toRadixString(16).padLeft(8, "0")}'));
    }
    // out 参数的 operation 引用与 Completed 传入的是同一对象,回调内统一
    // Release,此处不再重复释放。
    return completer.future;
  }

  Pointer<Uint8> _virtualDeviceName() {
    if (_virtualNameCache != null) return _virtualNameCache!;
    const name = 'VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK';
    final units = name.codeUnits;
    final buf = malloc<Uint16>(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      buf[i] = units[i];
    }
    buf[units.length] = 0;
    return _virtualNameCache = buf.cast();
  }
  Pointer<WaveFormatEx> _makeFormat() {
    final wfx = malloc<WaveFormatEx>();
    final blockAlign = targetChannels * 4;
    final sub = _subformatIeeeFloat.ref;
    wfx.ref
      ..formatTag = 0xFFFE // WAVE_FORMAT_EXTENSIBLE
      ..channels = targetChannels
      ..samplesPerSec = targetSampleRate
      ..avgBytesPerSec = targetSampleRate * blockAlign
      ..blockAlign = blockAlign
      ..bitsPerSample = 32
      ..cbSize = 22
      ..validBits = 32
      ..channelMask = 0x3; // stereo
    wfx.ref.subFormat.data1 = sub.data1;
    wfx.ref.subFormat.data2 = sub.data2;
    wfx.ref.subFormat.data3 = sub.data3;
    for (var i = 0; i < 8; i++) {
      wfx.ref.subFormat.data4[i] = sub.data4[i];
    }
    return wfx;
  }

  static Pointer<Uint8>? _virtualNameCache;
}
