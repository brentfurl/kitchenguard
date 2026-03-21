import 'package:flutter/material.dart';

import '../application/jobs_service.dart';
import '../application/startup_service.dart';
import '../storage/job_scanner.dart';
import 'job_detail.dart';

class JobsHome extends StatefulWidget {
  const JobsHome({super.key, required this.startup, required this.jobs});

  final StartupService startup;
  final JobsService jobs;

  @override
  State<JobsHome> createState() => _JobsHomeState();
}

class _JobsHomeState extends State<JobsHome> {
  bool _isLoading = true;
  List<JobScanResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final loaded = await widget.startup.loadJobs();
      final sorted = _sortJobsNewestFirst(loaded);
      if (!mounted) return;
      setState(() {
        _results = sorted;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String?> _showCreateJobDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Job'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Restaurant name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createJob() async {
    final input = await _showCreateJobDialog();
    if (input == null || !mounted) return;

    final restaurantName = input.trim();
    if (restaurantName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Restaurant name required')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.jobs.createJob(
        restaurantName: restaurantName,
        shiftStartLocal: DateTime.now(),
      );
      await _loadJobs();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openJobDetail(JobScanResult job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobDetail(jobs: widget.jobs, job: job),
      ),
    );
    if (!mounted) return;
    await _loadJobs();
  }

  List<JobScanResult> _sortJobsNewestFirst(List<JobScanResult> jobs) {
    final indexed = jobs.asMap().entries.toList();
    indexed.sort((a, b) {
      final left = _jobSortDate(a.value);
      final right = _jobSortDate(b.value);
      if (left != null && right != null) {
        final cmp = right.compareTo(left);
        if (cmp != 0) {
          return cmp;
        }
      } else if (left != null) {
        return -1;
      } else if (right != null) {
        return 1;
      }
      return a.key.compareTo(b.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  DateTime? _jobSortDate(JobScanResult result) {
    DateTime? parse(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return DateTime.tryParse(trimmed);
    }

    final createdAt = parse(result.job.createdAt);
    if (createdAt != null) {
      return createdAt.toUtc();
    }
    final shiftStartDate = parse(result.job.shiftStartDate);
    if (shiftStartDate != null) {
      return shiftStartDate.toUtc();
    }
    return null;
  }

  Future<void> _confirmDeleteJob(JobScanResult job) async {
    final name = job.job.restaurantName.isNotEmpty
        ? job.job.restaurantName
        : 'this job';
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Job?'),
          content: Text(
            'Delete "$name" and all its local files from this device?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      await widget.jobs.deleteJob(jobDir: job.jobDir);
      await _loadJobs();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_results.isEmpty) {
      body = const Center(child: Text('No jobs found.'));
    } else {
      body = ListView.builder(
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final result = _results[index];
          final restaurant = result.job.restaurantName.isNotEmpty
              ? result.job.restaurantName
              : 'Unknown';
          final shiftStart = result.job.shiftStartDate;

          return ListTile(
            title: Text(restaurant),
            subtitle: Text(shiftStart),
            onTap: () => _openJobDetail(result),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  await _confirmDeleteJob(result);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('Delete Job'),
                ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('KitchenGuard Jobs')),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _createJob,
        icon: const Icon(Icons.add),
        label: const Text('Create Job'),
      ),
    );
  }
}
