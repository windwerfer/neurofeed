import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// About + third-party notices screen. Loads the bundled
/// `THIRD_PARTY_NOTICES.md` (the single source of truth for credits) and shows
/// it as plain text.
class AboutView extends StatefulWidget {
  const AboutView({super.key});

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  Future<String>? _notices;

  @override
  void initState() {
    super.initState();
    _notices = rootBundle.loadString('THIRD_PARTY_NOTICES.md');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About & Notices')),
      body: FutureBuilder<String>(
        future: _notices,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load notices: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              snapshot.data!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.4,
              ),
            ),
          );
        },
      ),
    );
  }
}