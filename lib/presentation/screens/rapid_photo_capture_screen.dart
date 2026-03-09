import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RapidPhotoCaptureScreen extends StatefulWidget {
  const RapidPhotoCaptureScreen({
    super.key,
    required this.unitName,
    required this.phaseLabel,
    required this.loadVisibleCount,
    required this.onCaptureFile,
  });

  final String unitName;
  final String phaseLabel;
  final Future<int> Function() loadVisibleCount;
  final Future<void> Function(File file) onCaptureFile;

  @override
  State<RapidPhotoCaptureScreen> createState() =>
      _RapidPhotoCaptureScreenState();
}

class _RapidPhotoCaptureScreenState extends State<RapidPhotoCaptureScreen> {
  CameraController? _cameraController;
  bool _isInitializing = true;
  bool _isCapturing = false;
  int _visibleCount = 0;
  String? _initError;
  String? _inlineStatus;
  Timer? _statusTimer;
  Timer? _flashTimer;
  bool _showFlash = false;

  @override
  void initState() {
    super.initState();
    _lockPortrait();
    _initialize();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _flashTimer?.cancel();
    _restoreOrientation();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _lockPortrait() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  Future<void> _restoreOrientation() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _initialize() async {
    try {
      final initialCount = await widget.loadVisibleCount();
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera available on this device.');
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _visibleCount = initialCount;
        _isInitializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _initError = error.toString();
      });
    }
  }

  Future<void> _captureAndPersist() async {
    final camera = _cameraController;
    if (_isCapturing || camera == null || !camera.value.isInitialized) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final shot = await camera.takePicture();
      await widget.onCaptureFile(File(shot.path));
      final latestCount = await widget.loadVisibleCount();
      if (!mounted) return;
      await HapticFeedback.lightImpact();
      _flashTimer?.cancel();
      setState(() {
        _visibleCount = latestCount;
        _inlineStatus = 'Saved';
        _showFlash = true;
      });
      _flashTimer = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        setState(() {
          _showFlash = false;
        });
      });
      _statusTimer?.cancel();
      _statusTimer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() {
          _inlineStatus = null;
        });
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Capture failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Rapid Capture')),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : _initError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _initError!,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.unitName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.phaseLabel} • $_visibleCount photos',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.black,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_cameraController!),
                        IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _showFlash ? 0.18 : 0,
                            duration: const Duration(milliseconds: 90),
                            child: Container(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 18,
                        child: AnimatedOpacity(
                          opacity: _inlineStatus == null ? 0 : 1,
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            _inlineStatus ?? '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: SizedBox(
                          width: 84,
                          height: 84,
                          child: FilledButton(
                            onPressed: _isCapturing ? null : _captureAndPersist,
                            style: FilledButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            child: _isCapturing
                                ? const SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt_outlined,
                                    size: 32,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
