import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../application/jobs_service.dart';
import 'controllers/job_detail_controller.dart';
import 'screens/photo_viewer_screen.dart';
import 'screens/unit_photo_bucket_screen.dart';
import 'screens/videos_screen.dart';
import '../storage/job_scanner.dart';

class JobDetail extends StatefulWidget {
  const JobDetail({super.key, required this.jobs, required this.job});

  final JobsService jobs;
  final JobScanResult job;

  @override
  State<JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends State<JobDetail> {
  late final JobDetailController _controller;
  late Map<String, dynamic> _jobData;
  bool _isBusy = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _controller = JobDetailController(
      jobs: widget.jobs,
      jobDir: widget.job.jobDir,
    );
    _jobData = Map<String, dynamic>.from(widget.job.jobData);
  }

  int _countActivePhotos(dynamic list) {
    if (list is! List) {
      return 0;
    }

    var count = 0;
    for (final item in list) {
      if (item is! Map) {
        continue;
      }
      final status = (item['status'] ?? 'local').toString();
      if (status != 'deleted') {
        count += 1;
      }
    }

    return count;
  }

  String _bucketLabel(String bucket, int count) => '$bucket ($count)';

  Future<void> _addUnitFlow() async {
    final request = await _showAddUnitDialog();
    if (request == null || !mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      await widget.jobs.addUnit(
        jobDir: widget.job.jobDir,
        unitName: request.unitName,
        unitType: request.unitType,
      );
      await _reloadJobJson();
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString();
      final cleaned = raw.replaceFirst(RegExp(r'^StateError:\s*'), '');
      final message = cleaned.contains('Unit name already exists')
          ? 'Unit "${request.unitName}" already exists.'
          : cleaned;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _reloadJobJson() async {
    final jobJsonFile = File(p.join(widget.job.jobDir.path, 'job.json'));
    final fresh = await widget.jobs.jobStore.readJobJson(jobJsonFile);
    if (fresh == null) {
      throw StateError(
        'job.json missing after update: ${widget.job.jobDir.path}',
      );
    }

    if (!mounted) return;
    setState(() {
      _jobData = fresh;
    });
  }

  Future<void> _openVideosScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideosScreen(
          loadExitVideos: () => _controller.loadVideos(kind: 'exit'),
          loadOtherVideos: () => _controller.loadVideos(kind: 'other'),
          captureExit: () async {
            await _controller.captureVideo(kind: 'exit', picker: _picker);
            await _reloadJobJson();
          },
          captureOther: () async {
            await _controller.captureVideo(kind: 'other', picker: _picker);
            await _reloadJobJson();
          },
          softDelete: (kind, relativePath) async {
            await _controller.softDeleteVideo(
              kind: kind,
              relativePath: relativePath,
            );
            await _reloadJobJson();
          },
          resolveVideoFile: (relativePath) async {
            final file = _controller.videoFileFromRelativePath(relativePath);
            return await file.exists() ? file : null;
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadJobJson();
  }

  Future<void> _exportJob() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Exporting job...')),
              ],
            ),
          ),
        );
      },
    );

    try {
      final restaurantName = (_jobData['restaurantName'] ?? 'KitchenGuard_Job')
          .toString();
      final zipFile = await _controller.exportJobZip(
        jobDisplayName: restaurantName,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await Share.shareXFiles([
        XFile(zipFile.path),
      ], text: 'KitchenGuard job export');
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|Exception):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Failed to export job' : message),
        ),
      );
    }
  }

  Future<_AddUnitRequest?> _showAddUnitDialog() {
    final nameController = TextEditingController();
    String selectedType = 'hood';

    return showDialog<_AddUnitRequest>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Unit'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Unit name'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Unit type'),
                    items: const [
                      DropdownMenuItem(value: 'hood', child: Text('hood')),
                      DropdownMenuItem(value: 'fan', child: Text('fan')),
                      DropdownMenuItem(value: 'misc', child: Text('misc')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedType = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final unitName = nameController.text.trim();
                    if (unitName.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a unit name.'),
                        ),
                      );
                      return;
                    }

                    Navigator.of(context).pop(
                      _AddUnitRequest(
                        unitName: unitName,
                        unitType: selectedType,
                      ),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final restaurantName = (_jobData['restaurantName'] ?? 'Unknown').toString();
    final shiftStartDate = (_jobData['shiftStartDate'] ?? '').toString();
    final units = (_jobData['units'] as List?) ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(restaurantName),
        actions: [
          IconButton(
            onPressed: _exportJob,
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Export Job',
          ),
          TextButton(onPressed: _openVideosScreen, child: const Text('Videos')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              shiftStartDate,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Units',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: units.isEmpty
                ? const Center(child: Text('No units yet.'))
                : ListView.builder(
                    itemCount: units.length,
                    itemBuilder: (context, index) {
                      final unit = units[index];
                      if (unit is! Map) {
                        return const ListTile(
                          title: Text('Invalid unit entry'),
                        );
                      }
                      final unitId = (unit['unitId'] ?? '').toString();
                      final name = (unit['name'] ?? '').toString();
                      final type = (unit['type'] ?? '').toString();
                      final beforeCount = _countActivePhotos(
                        unit['photosBefore'],
                      );
                      final afterCount = _countActivePhotos(
                        unit['photosAfter'],
                      );

                      return ListTile(
                        key: ValueKey(unitId),
                        title: Text(name.isEmpty ? 'Unnamed unit' : name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(type),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isBusy
                                        ? null
                                        : () async {
                                            final unitName =
                                                (unit['name'] ?? '').toString();
                                            await Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => UnitPhotoBucketScreen(
                                                  title: '$unitName — Before',
                                                  jobDir: widget.job.jobDir,
                                                  loadPhotos: () async {
                                                    final job =
                                                        await _controller
                                                            .loadJob();
                                                    final u = _controller
                                                        .findUnitById(
                                                          job,
                                                          unitId,
                                                        );
                                                    return (u == null)
                                                        ? <
                                                            Map<String, dynamic>
                                                          >[]
                                                        : _controller
                                                              .bucketPhotos(
                                                                u,
                                                                'before',
                                                              );
                                                  },
                                                  onCapture: () async {
                                                    final job =
                                                        await _controller
                                                            .loadJob();
                                                    final u = _controller
                                                        .findUnitById(
                                                          job,
                                                          unitId,
                                                        );
                                                    if (u == null) {
                                                      throw StateError(
                                                        'Unit not found',
                                                      );
                                                    }
                                                    await _controller
                                                        .capturePhoto(
                                                          unit: u,
                                                          phase: 'before',
                                                          picker: _picker,
                                                        );
                                                  },
                                                  onJobMutated: () async {
                                                    await _reloadJobJson();
                                                  },
                                                  onSoftDelete:
                                                      (relativePath) async {
                                                        await _controller
                                                            .softDeletePhoto(
                                                              unitId: unitId,
                                                              phase: 'before',
                                                              relativePath:
                                                                  relativePath,
                                                            );
                                                      },
                                                  onOpenViewer: (initialIndex, photos) {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute<void>(
                                                        builder: (_) => PhotoViewerScreen(
                                                          jobDir:
                                                              widget.job.jobDir,
                                                          title:
                                                              '$unitName — Before',
                                                          photos: photos,
                                                          initialIndex:
                                                              initialIndex,
                                                          onSoftDelete:
                                                              (
                                                                relativePath,
                                                              ) => _controller
                                                                  .softDeletePhoto(
                                                                    unitId:
                                                                        unitId,
                                                                    phase:
                                                                        'before',
                                                                    relativePath:
                                                                        relativePath,
                                                                  ),
                                                          onJobMutated: () async {
                                                            await _reloadJobJson();
                                                          },
                                                          reloadPhotos: () async {
                                                            final job =
                                                                await _controller
                                                                    .loadJob();
                                                            final u = _controller
                                                                .findUnitById(
                                                                  job,
                                                                  unitId,
                                                                );
                                                            return (u == null)
                                                                ? <
                                                                    Map<
                                                                      String,
                                                                      dynamic
                                                                    >
                                                                  >[]
                                                                : _controller
                                                                      .bucketPhotos(
                                                                        u,
                                                                        'before',
                                                                      );
                                                          },
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            );
                                            if (!mounted) return;
                                            await _reloadJobJson();
                                          },
                                    child: Text(
                                      _bucketLabel('Before', beforeCount),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isBusy
                                        ? null
                                        : () async {
                                            final unitName =
                                                (unit['name'] ?? '').toString();
                                            await Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => UnitPhotoBucketScreen(
                                                  title: '$unitName — After',
                                                  jobDir: widget.job.jobDir,
                                                  loadPhotos: () async {
                                                    final job =
                                                        await _controller
                                                            .loadJob();
                                                    final u = _controller
                                                        .findUnitById(
                                                          job,
                                                          unitId,
                                                        );
                                                    return (u == null)
                                                        ? <
                                                            Map<String, dynamic>
                                                          >[]
                                                        : _controller
                                                              .bucketPhotos(
                                                                u,
                                                                'after',
                                                              );
                                                  },
                                                  onCapture: () async {
                                                    final job =
                                                        await _controller
                                                            .loadJob();
                                                    final u = _controller
                                                        .findUnitById(
                                                          job,
                                                          unitId,
                                                        );
                                                    if (u == null) {
                                                      throw StateError(
                                                        'Unit not found',
                                                      );
                                                    }
                                                    await _controller
                                                        .capturePhoto(
                                                          unit: u,
                                                          phase: 'after',
                                                          picker: _picker,
                                                        );
                                                  },
                                                  onJobMutated: () async {
                                                    await _reloadJobJson();
                                                  },
                                                  onSoftDelete:
                                                      (relativePath) async {
                                                        await _controller
                                                            .softDeletePhoto(
                                                              unitId: unitId,
                                                              phase: 'after',
                                                              relativePath:
                                                                  relativePath,
                                                            );
                                                      },
                                                  onOpenViewer: (initialIndex, photos) {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute<void>(
                                                        builder: (_) => PhotoViewerScreen(
                                                          jobDir:
                                                              widget.job.jobDir,
                                                          title:
                                                              '$unitName — After',
                                                          photos: photos,
                                                          initialIndex:
                                                              initialIndex,
                                                          onSoftDelete:
                                                              (
                                                                relativePath,
                                                              ) => _controller
                                                                  .softDeletePhoto(
                                                                    unitId:
                                                                        unitId,
                                                                    phase:
                                                                        'after',
                                                                    relativePath:
                                                                        relativePath,
                                                                  ),
                                                          onJobMutated: () async {
                                                            await _reloadJobJson();
                                                          },
                                                          reloadPhotos: () async {
                                                            final job =
                                                                await _controller
                                                                    .loadJob();
                                                            final u = _controller
                                                                .findUnitById(
                                                                  job,
                                                                  unitId,
                                                                );
                                                            return (u == null)
                                                                ? <
                                                                    Map<
                                                                      String,
                                                                      dynamic
                                                                    >
                                                                  >[]
                                                                : _controller
                                                                      .bucketPhotos(
                                                                        u,
                                                                        'after',
                                                                      );
                                                          },
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            );
                                            if (!mounted) return;
                                            await _reloadJobJson();
                                          },
                                    child: Text(
                                      _bucketLabel('After', afterCount),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _addUnitFlow,
        icon: const Icon(Icons.add),
        label: const Text('Add Unit'),
      ),
    );
  }
}

class _AddUnitRequest {
  const _AddUnitRequest({required this.unitName, required this.unitType});

  final String unitName;
  final String unitType;
}
