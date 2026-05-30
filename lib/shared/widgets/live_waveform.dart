import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import 'waveform_view.dart';

/// Кэш реальных waveform-сэмплов по URL на сессию + дедуп in-flight запросов.
/// Один трек встречается в списке, плеере и на странице — фетчим форму раз.
final Map<String, List<double>> _waveCache = {};
final Map<String, Future<List<double>?>> _inflight = {};

/// [WaveformView], который лениво подгружает РЕАЛЬНУЮ форму трека из
/// `waveformUrl` (с общим кэшем) и рисует её вместо процедурной заглушки.
/// Пока грузится / если не удалось — показывает [fallbackBars]. Убирает
/// расхождение «в списках/плеере одна форма, на странице трека другая».
class LiveWaveform extends ConsumerStatefulWidget {
  const LiveWaveform({
    super.key,
    required this.waveformUrl,
    required this.fallbackBars,
    this.progress = 0,
    this.buffered = 0,
    this.onSeek,
    this.height = 64,
    this.markers = const [],
  });

  final String? waveformUrl;
  final List<double> fallbackBars;
  final double progress;
  final double buffered;
  final ValueChanged<double>? onSeek;
  final double height;
  final List<double> markers;

  @override
  ConsumerState<LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends ConsumerState<LiveWaveform> {
  List<double>? _real;

  @override
  void initState() {
    super.initState();
    _real = _waveCache[widget.waveformUrl];
    _load();
  }

  @override
  void didUpdateWidget(LiveWaveform old) {
    super.didUpdateWidget(old);
    if (old.waveformUrl != widget.waveformUrl) {
      _real = _waveCache[widget.waveformUrl];
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.waveformUrl;
    if (url == null || url.isEmpty || _waveCache.containsKey(url)) return;
    final future = _inflight[url] ??= ref
        .read(soundcloudApiProvider)
        .fetchWaveform(url);
    final res = await future;
    _inflight.remove(url);
    if (res == null || res.isEmpty) return;
    _waveCache[url] = res;
    if (mounted && widget.waveformUrl == url) setState(() => _real = res);
  }

  @override
  Widget build(BuildContext context) {
    return WaveformView(
      bars: _real ?? widget.fallbackBars,
      progress: widget.progress,
      buffered: widget.buffered,
      onSeek: widget.onSeek,
      height: widget.height,
      markers: widget.markers,
    );
  }
}
