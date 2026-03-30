import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class VideoCaptureScreen extends StatefulWidget {
  const VideoCaptureScreen({
    super.key,
    required this.title,
    required this.loadVideoCount,
    required this.onCaptureFile,
  });

  final String title;
  final Future<int> Function() loadVideoCount;
  final Future<void> Function(File file) onCaptureFile;

  @override
  State<VideoCaptureScreen> createState() => _VideoCaptureScreenState();
}

class _VideoCaptureScreenState extends State<VideoCaptureScreen> {
  CameraController? _cameraController;
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isSaving = false;
  int _videoCount = 0;
  String? _initError;
  String? _inlineStatus;
  Timer? _statusTimer;
  Timer? _durationTimer;
  Duration _recordingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _durationTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final initialCount = await widget.loadVideoCount();
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
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _videoCount = initialCount;
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

  Future<void> _startRecording() async {
    final camera = _cameraController;
    if (_isRecording ||
        _isSaving ||
        camera == null ||
        !camera.value.isInitialized) {
      return;
    }

    try {
      await camera.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
        _inlineStatus = null;
      });
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start recording: $error')),
      );
    }
  }

  Future<void> _stopRecording() async {
    final camera = _cameraController;
    if (!_isRecording || _isSaving || camera == null) {
      return;
    }

    _durationTimer?.cancel();
    setState(() {
      _isRecording = false;
      _isSaving = true;
    });

    try {
      final video = await camera.stopVideoRecording();
      await widget.onCaptureFile(File(video.path));
      final latestCount = await widget.loadVideoCount();
      if (!mounted) return;
      setState(() {
        _videoCount = latestCount;
        _isSaving = false;
        _inlineStatus = 'Saved';
        _recordingDuration = Duration.zero;
      });
      _statusTimer?.cancel();
      _statusTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        setState(() {
          _inlineStatus = null;
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _recordingDuration = Duration.zero;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save video: $error')),
      );
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_isRecording && !_isSaving,
      child: Scaffold(
        appBar: AppBar(),
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
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_videoCount videos',
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
                          child: CameraPreview(_cameraController!),
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
                              child: _isRecording
                                  ? Text(
                                      _formatDuration(_recordingDuration),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : AnimatedOpacity(
                                      opacity: _inlineStatus == null ? 0 : 1,
                                      duration:
                                          const Duration(milliseconds: 180),
                                      child: Text(
                                        _inlineStatus ?? '',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: SizedBox(
                                width: 84,
                                height: 84,
                                child: _isSaving
                                    ? const Center(
                                        child: SizedBox(
                                          width: 26,
                                          height: 26,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                          ),
                                        ),
                                      )
                                    : _isRecording
                                        ? _StopRecordButton(
                                            onPressed: _stopRecording,
                                          )
                                        : _StartRecordButton(
                                            onPressed: _startRecording,
                                          ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _StartRecordButton extends StatelessWidget {
  const _StartRecordButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _StopRecordButton extends StatelessWidget {
  const _StopRecordButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}
