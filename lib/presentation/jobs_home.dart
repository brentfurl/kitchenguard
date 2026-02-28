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
      if (!mounted) return;
      setState(() {
        _results = loaded;
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
    final controller = TextEditingController(text: 'Test_Restaurant');
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
          final data = _results[index].jobData;
          final restaurant = (data['restaurantName'] ?? 'Unknown').toString();
          final shiftStart = (data['shiftStartDate'] ?? '').toString();

          return ListTile(
            title: Text(restaurant),
            subtitle: Text(shiftStart),
            onTap: () => _openJobDetail(_results[index]),
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
