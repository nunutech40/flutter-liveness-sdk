import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_liveness_sdk/flutter_liveness_sdk.dart';

void main() => runApp(const MaterialApp(home: Demo()));

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  final Set<LivenessStep> _selectedSteps = LivenessStep.values.toSet();
  final List<String> _events = [];
  StreamSubscription<LivenessEvent>? _subscription;
  LivenessResult? _result;
  bool _auditMode = true;
  bool _busy = false;
  int _timeoutSeconds = 30;
  String _status = 'Siap untuk mencoba';
  String? _error;

  static const _stepLabels = {
    LivenessStep.lookLeft: 'Lihat kiri',
    LivenessStep.lookRight: 'Lihat kanan',
    LivenessStep.smile: 'Senyum',
    LivenessStep.blink: 'Kedip',
  };

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _record(String message) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, '${TimeOfDay.now().format(context)}  $message');
      if (_events.length > 50) _events.removeLast();
    });
  }

  String _eventDescription(LivenessEvent event) {
    switch (event.type) {
      case 'ready':
        return 'Kamera siap · ${_stepLabels[event.step] ?? 'menunggu aksi'}';
      case 'stepPassed':
        return 'Lolos · ${_stepLabels[event.step] ?? event.step?.name ?? '-'}';
      case 'guidance':
        return switch (event.code) {
          'no_face' => 'Wajah belum terlihat',
          'multiple_faces' => 'Terdeteksi lebih dari satu wajah',
          _ => 'Petunjuk · ${event.code ?? '-'}',
        };
      default:
        return '${event.type} · ${event.message ?? event.code ?? '-'}';
    }
  }

  Future<void> _capture() async {
    if (_busy || _selectedSteps.isEmpty) return;
    final steps = LivenessStep.values
        .where(_selectedSteps.contains)
        .toList(growable: false);
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
      _events.clear();
      _status = 'Membuka kamera…';
    });
    await _subscription?.cancel();
    _subscription = FlutterLivenessSdk.events.listen((event) {
      final description = _eventDescription(event);
      _record(description);
      if (mounted) setState(() => _status = description);
    }, onError: (Object error) => _record('Event error: $error'));

    try {
      final result = await FlutterLivenessSdk.capture(
        LivenessConfig(
          steps: steps,
          auditMode: _auditMode,
          timeout: Duration(seconds: _timeoutSeconds),
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _status = switch (result.status) {
          LivenessStatus.success => 'Berhasil',
          LivenessStatus.cancelled => 'Dibatalkan',
          LivenessStatus.timedOut => 'Waktu habis',
          LivenessStatus.failed => 'Gagal',
        };
      });
      _record(
        'Selesai · ${result.status.name}'
        '${result.errorCode == null ? '' : ' (${result.errorCode})'}',
      );
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _status = 'Gagal membuka sesi';
          _error = '${error.code}: ${error.message ?? 'Tidak ada detail'}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = 'Gagal membuka sesi';
          _error = '$error';
        });
      }
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await FlutterLivenessSdk.cancel();
    } catch (error) {
      if (mounted) setState(() => _error = 'Gagal membatalkan: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liveness SDK · Test Lab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Uji library langsung dari example app ini. Pilih aksi lalu jalankan kamera native. Hasil foto dan event akan muncul di bawah.',
          ),
          const SizedBox(height: 20),
          Text('Aksi wajah', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final step in LivenessStep.values)
            CheckboxListTile(
              title: Text(_stepLabels[step]!),
              subtitle: Text(step.name),
              value: _selectedSteps.contains(step),
              onChanged: _busy
                  ? null
                  : (selected) => setState(() {
                      if (selected ?? false) {
                        _selectedSteps.add(step);
                      } else {
                        _selectedSteps.remove(step);
                      }
                    }),
              contentPadding: EdgeInsets.zero,
            ),
          if (_selectedSteps.isEmpty)
            const Text(
              'Pilih minimal satu aksi.',
              style: TextStyle(color: Colors.red),
            ),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('Audit mode'),
            subtitle: const Text(
              'Simpan bukti foto untuk setiap aksi yang lolos',
            ),
            value: _auditMode,
            onChanged: _busy
                ? null
                : (value) => setState(() => _auditMode = value),
            contentPadding: EdgeInsets.zero,
          ),
          Text('Timeout: $_timeoutSeconds detik'),
          Slider(
            value: _timeoutSeconds.toDouble(),
            min: 15,
            max: 90,
            divisions: 5,
            label: '$_timeoutSeconds detik',
            onChanged: _busy
                ? null
                : (value) => setState(() => _timeoutSeconds = value.round()),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy || _selectedSteps.isEmpty ? null : _capture,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Mulai tes liveness'),
          ),
          if (_busy)
            OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.close),
              label: const Text('Batalkan sesi'),
            ),
          const SizedBox(height: 20),
          _sectionTitle('Status'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_status, style: Theme.of(context).textTheme.titleMedium),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  if (_result?.errorCode != null) ...[
                    const SizedBox(height: 8),
                    SelectableText('Kode: ${_result!.errorCode}'),
                  ],
                ],
              ),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 20),
            _sectionTitle('Hasil foto'),
            if (_result!.selfiePath != null)
              _imageCard('Selfie', _result!.selfiePath!),
            for (final entry in _result!.evidencePaths.entries)
              _imageCard(_stepLabels[entry.key] ?? entry.key.name, entry.value),
            if (_result!.selfiePath == null && _result!.evidencePaths.isEmpty)
              const Text('Tidak ada foto yang dikembalikan.'),
            const SizedBox(height: 8),
            const Text(
              'Foto disimpan sementara di cache aplikasi. Simpan atau hapus sesuai kebutuhan produk.',
            ),
          ],
          const SizedBox(height: 20),
          _sectionTitle('Event (${_events.length})'),
          if (_events.isEmpty)
            const Text(
              'Belum ada event. Jalankan satu sesi untuk melihat progres.',
            ),
          for (final event in _events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: SelectableText(event),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);

  Widget _imageCard(String title, String path) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Image.file(
            File(path),
            height: 240,
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const Text('Foto tidak dapat dibuka dari path ini.'),
          ),
          const SizedBox(height: 8),
          SelectableText(path),
        ],
      ),
    ),
  );
}
