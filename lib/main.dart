import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'core/models.dart';
import 'core/services.dart';
import 'core/theme.dart';

final NumberFormat _currencyFormat =
    NumberFormat.currency(locale: 'en_IN', symbol: 'Rs ', decimalDigits: 0);
final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');

String money(double value) => _currencyFormat.format(value);

String titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

Color stageColor(String stage, BuildContext context) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  switch (stage) {
    case 'won':
      return scheme.primary;
    case 'lost':
      return scheme.error;
    case 'proposal':
      return Colors.amber.shade700;
    case 'negotiation':
      return Colors.deepOrange.shade400;
    case 'qualified':
      return Colors.teal.shade400;
    default:
      return Colors.blue.shade400;
  }
}

Future<void> exportCsv(BuildContext context, List<Lead> leads) async {
  final List<List<String>> rows = <List<String>>[
    <String>[
      'Company',
      'Contact',
      'Email',
      'Phone',
      'Source',
      'Stage',
      'Value (INR)',
      'Assigned To',
      'Last Touch',
      'Notes',
    ],
    ...leads.map(
      (Lead lead) => <String>[
        lead.companyName,
        lead.contactName,
        lead.contactEmail,
        lead.contactPhone,
        lead.source,
        lead.stage,
        lead.estimatedValue.toStringAsFixed(0),
        lead.assignedTo,
        lead.lastTouch,
        lead.notes.replaceAll(RegExp(r'[\r\n,]'), ' '),
      ],
    ),
  ];

  final String csv = rows
      .map((List<String> row) => row.map((String cell) => '"$cell"').join(','))
      .join('\n');

  final Directory dir = await getTemporaryDirectory();
  final File file = File(
    '${dir.path}\\smartcrm-leads-${DateTime.now().toIso8601String().split('T').first}.csv',
  );
  await file.writeAsString('\uFEFF$csv');
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[XFile(file.path)],
      text: 'SmartCRM lead export',
    ),
  );
}

Future<void> exportPdf(
  BuildContext context,
  List<Lead> leads,
  PipelineStats stats,
) async {
  final pw.Document pdf = pw.Document();

  pdf.addPage(
    pw.MultiPage(
      build: (pw.Context context) => <pw.Widget>[
        pw.Text(
          'SmartCRM Lead Report',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Generated ${DateTime.now()}'),
        pw.SizedBox(height: 16),
        pw.Wrap(
          spacing: 16,
          runSpacing: 16,
          children: <pw.Widget>[
            _pdfMetric('Total Pipeline', money(stats.totalValue)),
            _pdfMetric('Won Revenue', money(stats.wonValue)),
            _pdfMetric('Conversion', '${stats.conversionRate}%'),
            _pdfMetric('Leads', '${leads.length}'),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: <String>[
            '#',
            'Company',
            'Contact',
            'Source',
            'Stage',
            'Value',
            'Last Touch',
          ],
          data: List<List<String>>.generate(
            leads.length,
            (int index) {
              final Lead lead = leads[index];
              return <String>[
                '${index + 1}',
                lead.companyName,
                lead.contactName,
                lead.source,
                lead.stage,
                money(lead.estimatedValue),
                lead.lastTouch,
              ];
            },
          ),
        ),
      ],
    ),
  );

  await Printing.sharePdf(
    bytes: await pdf.save(),
    filename: 'smartcrm-report.pdf',
  );
}

pw.Widget _pdfMetric(String label, String value) {
  return pw.Container(
    width: 120,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 6),
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  bool firebaseReady = false;
  String? firebaseError;

  try {
    if (FirebaseEnvConfig.isConfiguredForCurrentPlatform) {
      await Firebase.initializeApp(options: FirebaseEnvConfig.currentPlatform);
      firebaseReady = true;
    }
  } catch (error) {
    firebaseError = error.toString();
  }

  final ThemeMode themeMode =
      (prefs.getString('smartcrm-theme') ?? 'dark') == 'light'
          ? ThemeMode.light
          : ThemeMode.dark;

  runApp(
    SmartCmrApp(
      prefs: prefs,
      firebaseReady: firebaseReady,
      firebaseError: firebaseError,
      themeMode: themeMode,
    ),
  );
}

class SmartCmrApp extends StatefulWidget {
  const SmartCmrApp({
    super.key,
    required this.prefs,
    required this.firebaseReady,
    required this.firebaseError,
    required this.themeMode,
  });

  final SharedPreferences prefs;
  final bool firebaseReady;
  final String? firebaseError;
  final ThemeMode themeMode;

  @override
  State<SmartCmrApp> createState() => _SmartCmrAppState();
}

class _SmartCmrAppState extends State<SmartCmrApp> {
  late ThemeMode _themeMode = widget.themeMode;
  late final Stream<fb_auth.User?> _authStream = FirebaseAuthService.instance.authChanges;
  WorkspaceView _view = WorkspaceView.pipeline;
  String _stageFilter = 'all';
  String _minValue = '';
  String _maxValue = '';
  String? _selectedLeadId;
  String? _editLeadId;
  final TextEditingController _search = TextEditingController();
  final TextEditingController _aiPrompt = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _aiPrompt.dispose();
    super.dispose();
  }

  Future<void> _toggleTheme() async {
    final ThemeMode next =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await widget.prefs.setString(
      'smartcrm-theme',
      next == ThemeMode.light ? 'light' : 'dark',
    );
    setState(() => _themeMode = next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartCRM',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: widget.firebaseReady
          ? StreamBuilder<fb_auth.User?>(
              stream: _authStream,
              builder: (
                BuildContext context,
                AsyncSnapshot<fb_auth.User?> snapshot,
              ) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SplashScreen();
                }
                if (snapshot.data == null) {
                  return PublicScreen(
                    themeMode: _themeMode,
                    onToggleTheme: _toggleTheme,
                  );
                }
                return WorkspaceScreen(
                  themeMode: _themeMode,
                  onToggleTheme: _toggleTheme,
                  user: snapshot.data!,
                  view: _view,
                  onViewChanged: (v) => setState(() => _view = v),
                  stageFilter: _stageFilter,
                  onStageFilterChanged: (s) => setState(() => _stageFilter = s),
                  minValue: _minValue,
                  onMinValueChanged: (m) => setState(() => _minValue = m),
                  maxValue: _maxValue,
                  onMaxValueChanged: (m) => setState(() => _maxValue = m),
                  selectedLeadId: _selectedLeadId,
                  onSelectedLeadIdChanged: (id) => setState(() => _selectedLeadId = id),
                  editLeadId: _editLeadId,
                  onEditLeadIdChanged: (id) => setState(() => _editLeadId = id),
                  searchController: _search,
                  aiPromptController: _aiPrompt,
                );
              },
            )
          : SetupScreen(
              themeMode: _themeMode,
              onToggleTheme: _toggleTheme,
              firebaseError: widget.firebaseError,
            ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const BrandLogoText(size: 72),
            const SizedBox(height: 20),
            Text(
              'SmartCRM',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('Loading…', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
    required this.firebaseError,
  });

  final ThemeMode themeMode;
  final Future<void> Function() onToggleTheme;
  final String? firebaseError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartCRM Setup', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: <Widget>[
          IconButton(
            onPressed: onToggleTheme,
            icon: Icon(
              themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Center(child: BrandLogoText(size: 72)),
          const SizedBox(height: 18),
          const SectionCard(
            child: SelectableText(
              'Run with Firebase values using --dart-define, then start the app.\n\n'
              'Required Android values:\n'
              'FIREBASE_PROJECT_ID\n'
              'FIREBASE_MESSAGING_SENDER_ID\n'
              'FIREBASE_STORAGE_BUCKET\n'
              'FIREBASE_ANDROID_API_KEY\n'
              'FIREBASE_ANDROID_APP_ID\n\n'
              'Required iOS values:\n'
              'FIREBASE_PROJECT_ID\n'
              'FIREBASE_MESSAGING_SENDER_ID\n'
              'FIREBASE_STORAGE_BUCKET\n'
              'FIREBASE_IOS_API_KEY\n'
              'FIREBASE_IOS_APP_ID\n'
              'FIREBASE_IOS_BUNDLE_ID',
            ),
          ),
          if (firebaseError != null) ...<Widget>[
            const SizedBox(height: 12),
            SectionCard(child: SelectableText(firebaseError!)),
          ],
        ],
      ),
    );
  }
}

class PublicScreen extends StatefulWidget {
  const PublicScreen({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  final ThemeMode themeMode;
  final Future<void> Function() onToggleTheme;

  @override
  State<PublicScreen> createState() => _PublicScreenState();
}

class _PublicScreenState extends State<PublicScreen> {
  bool _authMode = false;
  bool _signInMode = true;
  bool _busy = false;
  String _error = '';

  final TextEditingController _inEmail = TextEditingController();
  final TextEditingController _inPassword = TextEditingController();
  final TextEditingController _upName = TextEditingController();
  final TextEditingController _upEmail = TextEditingController();
  final TextEditingController _upPassword = TextEditingController();
  final TextEditingController _upConfirm = TextEditingController();

  @override
  void dispose() {
    _inEmail.dispose();
    _inPassword.dispose();
    _upName.dispose();
    _upEmail.dispose();
    _upPassword.dispose();
    _upConfirm.dispose();
    super.dispose();
  }

  Future<void> _doSignIn() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await FirebaseAuthService.instance.signIn(
        emailOrUsername: _inEmail.text,
        password: _inPassword.text,
      );
    } catch (error) {
      setState(() => _error = friendlyAuthError(error.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doSignUp() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await FirebaseAuthService.instance.signUp(
        username: _upName.text,
        email: _upEmail.text,
        password: _upPassword.text,
        confirmPassword: _upConfirm.text,
      );
    } catch (error) {
      setState(() => _error = friendlyAuthError(error.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            BrandLogoText(size: 28),
            SizedBox(width: 10),
            Text('SmartCRM', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.themeMode == ThemeMode.light
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _authMode ? _buildAuth(context) : _buildLanding(context),
      ),
    );
  }

  Widget _buildLanding(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('landing'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const SizedBox(height: 24),
        const Center(child: BrandLogoText(size: 72)),
        const SizedBox(height: 16),
        Text(
          'Intelligent Lead Management',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.2,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Close more deals with smarter pipeline control',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'SmartCRM keeps lead tracking, reminders, communication logs, AI insights, and live reports in one app.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => setState(() {
            _authMode = true;
            _signInMode = false;
          }),
          child: const Text('Start for Free'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => setState(() {
            _authMode = true;
            _signInMode = true;
          }),
          child: const Text('Sign In'),
        ),
        const SizedBox(height: 18),
        const FeatureTile(
          icon: Icons.account_tree_outlined,
          title: 'Pipeline Tracker',
          description: 'Visualise every deal from New to Won in real time.',
        ),
        const FeatureTile(
          icon: Icons.notifications_active_outlined,
          title: 'Follow-up Reminders',
          description: 'Never miss next steps for any lead.',
        ),
        const FeatureTile(
          icon: Icons.history_edu_outlined,
          title: 'Communication Logs',
          description: 'Store every call, email, meeting, and chat note.',
        ),
        const FeatureTile(
          icon: Icons.auto_awesome_outlined,
          title: 'AI Assistant',
          description: 'Get pipeline summaries, priorities, and email drafts.',
        ),
        const SizedBox(height: 32),
        // Additional content
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'More Features Coming Soon...',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'We are constantly working to improve SmartCRM. Stay tuned for advanced analytics, integrations, and more!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        // Footer
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '© ${DateTime.now().year} SmartCRM. All rights reserved.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildAuth(BuildContext context) {
    return ListView(
      key: const ValueKey<String>('auth'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => setState(() {
              _authMode = false;
              _error = '';
            }),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 8,
          shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(child: BrandLogoText(size: 60)),
                const SizedBox(height: 12),
                Text(
                  'SmartCRM',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(value: true, label: Text('Sign In')),
                    ButtonSegment<bool>(value: false, label: Text('Create Account')),
                  ],
                  selected: <bool>{_signInMode},
                  onSelectionChanged: (Set<bool> value) {
                    setState(() {
                      _signInMode = value.first;
                      _error = '';
                    });
                  },
                ),
                const SizedBox(height: 18),
                if (_signInMode) ...<Widget>[
          TextField(
            controller: _inEmail,
            decoration: const InputDecoration(labelText: 'Email Address'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _inPassword,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _doSignIn,
            child: Text(_busy ? 'Signing In...' : 'Sign In'),
          ),
        ] else ...<Widget>[
          TextField(
            controller: _upName,
            decoration: const InputDecoration(labelText: 'Full Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _upEmail,
            decoration: const InputDecoration(labelText: 'Email Address'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _upPassword,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _upConfirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm Password'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _doSignUp,
            child: Text(_busy ? 'Creating Account...' : 'Create Account'),
          ),
        ],
                if (_error.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum WorkspaceView { pipeline, create, edit, reports, reminders, logs, ai, about, privacy, support }

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
    required this.user,
    required this.view,
    required this.onViewChanged,
    required this.stageFilter,
    required this.onStageFilterChanged,
    required this.minValue,
    required this.onMinValueChanged,
    required this.maxValue,
    required this.onMaxValueChanged,
    required this.selectedLeadId,
    required this.onSelectedLeadIdChanged,
    required this.editLeadId,
    required this.onEditLeadIdChanged,
    required this.searchController,
    required this.aiPromptController,
  });

  final ThemeMode themeMode;
  final Future<void> Function() onToggleTheme;
  final fb_auth.User user;
  final WorkspaceView view;
  final ValueChanged<WorkspaceView> onViewChanged;
  final String stageFilter;
  final ValueChanged<String> onStageFilterChanged;
  final String minValue;
  final ValueChanged<String> onMinValueChanged;
  final String maxValue;
  final ValueChanged<String> onMaxValueChanged;
  final String? selectedLeadId;
  final ValueChanged<String?> onSelectedLeadIdChanged;
  final String? editLeadId;
  final ValueChanged<String?> onEditLeadIdChanged;
  final TextEditingController searchController;
  final TextEditingController aiPromptController;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final CrmService _service = CrmService.instance;
  String? _error;
  String? _aiError;
  String _aiReply = '';
  bool _busy = false;
  bool _aiBusy = false;
  final Map<String, String> _stageDrafts = <String, String>{};

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onRebuild);
    widget.aiPromptController.addListener(_onRebuild);
  }

  void _onRebuild() => setState(() {});

  @override
  void dispose() {
    widget.searchController.removeListener(_onRebuild);
    widget.aiPromptController.removeListener(_onRebuild);
    super.dispose();
  }

  List<Lead> _filter(List<Lead> leads) {
    return leads.where((Lead lead) {
      bool ok = true;
      if (widget.stageFilter != 'all') ok = ok && lead.stage == widget.stageFilter;
      if (widget.minValue.isNotEmpty) {
        ok = ok && lead.estimatedValue >= (double.tryParse(widget.minValue) ?? 0);
      }
      if (widget.maxValue.isNotEmpty) {
        ok = ok &&
            lead.estimatedValue <= (double.tryParse(widget.maxValue) ?? double.infinity);
      }
      if (widget.searchController.text.trim().isNotEmpty) {
        final String term = widget.searchController.text.toLowerCase();
        ok = ok &&
            '${lead.companyName} ${lead.contactName} ${lead.contactEmail}'
                .toLowerCase()
                .contains(term);
      }
      return ok;
    }).toList();
  }

  Lead? _selectedLead(List<Lead> leads) {
    if (leads.isEmpty) return null;
    return leads.where((Lead l) => l.id == widget.selectedLeadId).cast<Lead?>().firstOrNull ??
        leads.first;
  }

  Lead? _editingLead(List<Lead> leads) {
    if (widget.editLeadId == null) return null;
    return leads.where((Lead l) => l.id == widget.editLeadId).cast<Lead?>().firstOrNull;
  }

  Future<void> _saveLead(LeadFormData form) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.view == WorkspaceView.create) {
        await _service.createLead(form);
      } else if (widget.editLeadId != null) {
        await _service.updateLead(widget.editLeadId!, form);
      }
      widget.onViewChanged(WorkspaceView.pipeline);
      widget.onEditLeadIdChanged(null);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _askAi(List<Lead> leads) async {
    setState(() {
      _aiBusy = true;
      _aiError = null;
      _aiReply = '';
    });
    try {
      final String reply =
          await _service.askAi(prompt: widget.aiPromptController.text.trim(), leads: leads);
      setState(() => _aiReply = reply);
    } catch (error) {
      setState(() => _aiError = error.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _moveStage(Lead lead) async {
    final String nextStage = _stageDrafts[lead.id] ?? lead.stage;
    if (nextStage == lead.stage) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.updateLead(
        lead.id,
        LeadFormData.fromLead(lead).copyWith(stage: nextStage),
      );
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Lead>>(
      stream: _service.watchLeads(),
      builder: (
        BuildContext context,
        AsyncSnapshot<List<Lead>> snapshot,
      ) {
        final List<Lead> leads = snapshot.data ?? <Lead>[];
        final PipelineStats stats = PipelineStats.fromLeads(leads);
        final List<Lead> filtered = _filter(leads);
        final Lead? selected = _selectedLead(leads);
        final Lead? editing = _editingLead(leads);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BrandLogoText(size: 26),
                const SizedBox(width: 10),
                Text(
                  _labelForView(widget.view),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: <Widget>[
              IconButton(
                onPressed: widget.onToggleTheme,
                icon: Icon(
                  widget.themeMode == ThemeMode.light
                      ? Icons.dark_mode
                      : Icons.light_mode,
                ),
                tooltip: 'Toggle theme',
              ),
              IconButton(
                onPressed: () => FirebaseAuthService.instance.signOut(),
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (widget.view) {
              WorkspaceView.create => LeadEditorView(
                  key: const ValueKey<String>('create'),
                  title: 'New Lead',
                  subtitle: 'Add a new prospect to your pipeline.',
                  busy: _busy,
                  errorText: _error,
                  submitLabel: 'Create Lead',
                  initialData: const LeadFormData(),
                  onSubmit: _saveLead,
                ),
              WorkspaceView.edit => LeadEditorView(
                  key: ValueKey<String>('edit-${editing?.id ?? "missing"}'),
                  title: 'Edit Lead',
                  subtitle: 'Update lead details.',
                  busy: _busy,
                  errorText: _error,
                  submitLabel: 'Save Changes',
                  initialData: editing == null
                      ? const LeadFormData()
                      : LeadFormData.fromLead(editing),
                  onSubmit: _saveLead,
                ),
              WorkspaceView.reports => ReportsView(
                  leads: leads,
                  stats: stats,
                  onExportCsv: () => exportCsv(context, leads),
                  onExportPdf: () => exportPdf(context, leads, stats),
                ),
              WorkspaceView.reminders => RemindersView(
                  leads: leads,
                  selectedLead: selected,
                  onSelectLead: (Lead? lead) =>
                      widget.onSelectedLeadIdChanged(lead?.id),
                  service: _service,
                ),
              WorkspaceView.logs => LogsView(
                  leads: leads,
                  selectedLead: selected,
                  onSelectLead: (Lead? lead) =>
                      widget.onSelectedLeadIdChanged(lead?.id),
                  service: _service,
                ),
              WorkspaceView.ai => AiView(
                  promptController: widget.aiPromptController,
                  busy: _aiBusy,
                  errorText: _aiError,
                  reply: _aiReply,
                  onAsk: () => _askAi(leads),
                ),
              WorkspaceView.about => const StaticPage(
                  title: 'About SmartCRM',
                  paragraphs: <String>[
                    'SmartCRM is a real-time lead management app for sales teams.',
                    'It includes pipeline tracking, reminders, logs, reports, and an AI assistant.',
                  ],
                ),
              WorkspaceView.privacy => const StaticPage(
                  title: 'Privacy',
                  paragraphs: <String>[
                    'Lead data is stored in Firebase Firestore.',
                    'AI prompts include pipeline context only when you use the assistant.',
                  ],
                ),
              WorkspaceView.support => const StaticPage(
                  title: 'Support',
                  paragraphs: <String>[
                    'Contact support@smartcrm.com with your account email and issue summary.',
                  ],
                ),
              WorkspaceView.pipeline => PipelineView(
                  leads: leads,
                  filteredLeads: filtered,
                  stats: stats,
                  searchController: widget.searchController,
                  stageFilter: widget.stageFilter,
                  minValue: widget.minValue,
                  maxValue: widget.maxValue,
                  stageDrafts: _stageDrafts,
                  busy: _busy,
                  errorText: _error,
                  onNewLead: () => widget.onViewChanged(WorkspaceView.create),
                  onSearchChanged: (_) => setState(() {}),
                  onStageFilterChanged: (String value) =>
                      widget.onStageFilterChanged(value),
                  onMinValueChanged: (String value) =>
                      widget.onMinValueChanged(value),
                  onMaxValueChanged: (String value) =>
                      widget.onMaxValueChanged(value),
                  onExportCsv: () => exportCsv(context, leads),
                  onExportPdf: () => exportPdf(context, leads, stats),
                  onStageDraftChanged: (Lead lead, String stage) =>
                      setState(() => _stageDrafts[lead.id] = stage),
                  onMoveStage: _moveStage,
                  onEditLead: (Lead lead) {
                    widget.onEditLeadIdChanged(lead.id);
                    widget.onViewChanged(WorkspaceView.edit);
                  },
                  onOpenLogs: (Lead lead) {
                    widget.onSelectedLeadIdChanged(lead.id);
                    widget.onViewChanged(WorkspaceView.logs);
                  },
                  onOpenReminders: (Lead lead) {
                    widget.onSelectedLeadIdChanged(lead.id);
                    widget.onViewChanged(WorkspaceView.reminders);
                  },
                ),
            },
          ),
        );
      },
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _navItem(WorkspaceView.pipeline, Icons.view_kanban_outlined, 'Pipeline'),
          _navItem(WorkspaceView.reports, Icons.bar_chart_outlined, 'Reports'),
          _navItem(WorkspaceView.ai, Icons.auto_awesome_outlined, 'AI'),
          _navItem(WorkspaceView.reminders, Icons.notifications_none, 'Tasks'),
          _navItem(WorkspaceView.logs, Icons.chat_bubble_outline, 'Logs'),
        ],
      ),
    );
  }

  Widget _navItem(WorkspaceView view, IconData icon, String label) {
    final bool isSelected = widget.view == view;
    final Color color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Colors.grey;
    return InkWell(
      onTap: () => widget.onViewChanged(view),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  String _labelForView(WorkspaceView view) {
    switch (view) {
      case WorkspaceView.pipeline:
        return 'Lead Pipeline';
      case WorkspaceView.create:
        return 'New Lead';
      case WorkspaceView.edit:
        return 'Edit Lead';
      case WorkspaceView.reports:
        return 'Conversion Reports';
      case WorkspaceView.reminders:
        return 'Reminders';
      case WorkspaceView.logs:
        return 'Communication Logs';
      case WorkspaceView.ai:
        return 'AI Assistant';
      case WorkspaceView.about:
        return 'About';
      case WorkspaceView.privacy:
        return 'Privacy';
      case WorkspaceView.support:
        return 'Support';
    }
  }
}

class PipelineView extends StatelessWidget {
  const PipelineView({
    super.key,
    required this.leads,
    required this.filteredLeads,
    required this.stats,
    required this.searchController,
    required this.stageFilter,
    required this.minValue,
    required this.maxValue,
    required this.stageDrafts,
    required this.busy,
    required this.errorText,
    required this.onSearchChanged,
    required this.onStageFilterChanged,
    required this.onMinValueChanged,
    required this.onMaxValueChanged,
    required this.onExportCsv,
    required this.onExportPdf,
    required this.onStageDraftChanged,
    required this.onMoveStage,
    required this.onEditLead,
    required this.onOpenLogs,
    required this.onOpenReminders,
    required this.onNewLead,
  });

  final List<Lead> leads;
  final List<Lead> filteredLeads;
  final PipelineStats stats;
  final TextEditingController searchController;
  final String stageFilter;
  final String minValue;
  final String maxValue;
  final Map<String, String> stageDrafts;
  final bool busy;
  final String? errorText;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStageFilterChanged;
  final ValueChanged<String> onMinValueChanged;
  final ValueChanged<String> onMaxValueChanged;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPdf;
  final void Function(Lead lead, String stage) onStageDraftChanged;
  final Future<void> Function(Lead lead) onMoveStage;
  final ValueChanged<Lead> onEditLead;
  final ValueChanged<Lead> onOpenLogs;
  final ValueChanged<Lead> onOpenReminders;
  final VoidCallback onNewLead;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('LEAD PIPELINE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Lead Pipeline', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  FilledButton.icon(
                    onPressed: onNewLead,
                    icon: const Icon(Icons.add),
                    label: const Text('New Lead'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: onExportCsv,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('CSV'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onExportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(title: 'PIPELINE VALUE', value: money(stats.totalValue), subtitle: '${leads.length} Active Leads'),
            MetricCard(title: 'WON REVENUE', value: money(stats.wonValue), subtitle: '${stats.wonCount ?? 0} Deals Won'),
            MetricCard(title: 'CONVERSION', value: '${stats.conversionRate}%', subtitle: 'Lead-to-Won rate'),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: stats.stageCounts.entries
                .map(
                  (MapEntry<String, int> entry) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: stageColor(entry.key, context).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(titleCase(entry.key)),
                        const SizedBox(height: 6),
                        Text('${entry.value}'),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            children: <Widget>[
              TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                decoration: const InputDecoration(
                  labelText: 'Search by company, name, or email',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: stageFilter,
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: 'all',
                    child: Text('All Stages'),
                  ),
                  ...kStages.map(
                    (String stage) => DropdownMenuItem<String>(
                      value: stage,
                      child: Text(titleCase(stage)),
                    ),
                  ),
                ],
                onChanged: (String? value) {
                  if (value != null) onStageFilterChanged(value);
                },
                decoration: const InputDecoration(labelText: 'Stage'),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      onChanged: onMinValueChanged,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Min value'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      onChanged: onMaxValueChanged,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Max value'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (filteredLeads.isEmpty)
          const SectionCard(child: Text('No leads match the current filter.')),
        ...filteredLeads.map((Lead lead) {
          final String nextStage = stageDrafts[lead.id] ?? lead.stage;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          lead.companyName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text(money(lead.estimatedValue)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      Chip(label: Text(lead.source)),
                      Chip(
                        label: Text(titleCase(lead.stage)),
                        backgroundColor:
                            stageColor(lead.stage, context).withOpacity(0.14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Contact: ${lead.contactName}'),
                  if (lead.contactEmail.isNotEmpty) Text('Email: ${lead.contactEmail}'),
                  if (lead.assignedTo.isNotEmpty) Text('Assigned: ${lead.assignedTo}'),
                  Text('Last touch: ${lead.lastTouch.isEmpty ? "-" : lead.lastTouch}'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: nextStage,
                    items: kStages
                        .map(
                          (String stage) => DropdownMenuItem<String>(
                            value: stage,
                            child: Text(titleCase(stage)),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      if (value != null) onStageDraftChanged(lead, value);
                    },
                    decoration: const InputDecoration(labelText: 'Move stage'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton(
                        onPressed: busy || nextStage == lead.stage
                            ? null
                            : () => onMoveStage(lead),
                        child: const Text('Move'),
                      ),
                      OutlinedButton(
                        onPressed: () => onEditLead(lead),
                        child: const Text('Edit'),
                      ),
                      OutlinedButton(
                        onPressed: () => onOpenLogs(lead),
                        child: const Text('Logs'),
                      ),
                      OutlinedButton(
                        onPressed: () => onOpenReminders(lead),
                        child: const Text('Tasks'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class ReportsView extends StatelessWidget {
  const ReportsView({
    super.key,
    required this.leads,
    required this.stats,
    required this.onExportCsv,
    required this.onExportPdf,
  });

  final List<Lead> leads;
  final PipelineStats stats;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPdf;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SectionCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Live Reports', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${leads.length} Active Leads Analyzed', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
                ],
              ),
              OutlinedButton.icon(
                onPressed: onExportCsv,
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: const Text('CSV'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(title: 'TOTAL PIPELINE', value: money(stats.totalValue), subtitle: 'Active Deals'),
            MetricCard(title: 'WON REVENUE', value: money(stats.wonValue), subtitle: '${stats.wonCount} deals won'),
            MetricCard(title: 'CONVERSION', value: '${stats.conversionRate}%', subtitle: 'Lead win rate'),
            MetricCard(title: 'AVG DEAL', value: money(stats.averageDeal), subtitle: 'Across all leads'),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('LEAD SOURCES', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.1, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              ...stats.sourceBreakdown.entries.map(
                (MapEntry<String, int> entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(titleCase(entry.key), style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text('${entry.value}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: leads.isEmpty ? 0 : entry.value / leads.length,
                        backgroundColor: Colors.grey.shade200,
                        color: Theme.of(context).colorScheme.primary,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RemindersView extends StatefulWidget {
  const RemindersView({
    super.key,
    required this.leads,
    required this.selectedLead,
    required this.onSelectLead,
    required this.service,
  });

  final List<Lead> leads;
  final Lead? selectedLead;
  final ValueChanged<Lead?> onSelectLead;
  final CrmService service;

  @override
  State<RemindersView> createState() => _RemindersViewState();
}

class _RemindersViewState extends State<RemindersView> {
  final TextEditingController _task = TextEditingController();
  DateTime? _dueAt;

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() {
      _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SectionCard(
          child: Column(
            children: <Widget>[
              DropdownButtonFormField<String>(
                value: widget.selectedLead?.id,
                items: widget.leads
                    .map(
                      (Lead lead) => DropdownMenuItem<String>(
                        value: lead.id,
                        child: Text(lead.companyName),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  final Lead? lead = widget.leads
                      .where((Lead item) => item.id == value)
                      .cast<Lead?>()
                      .firstOrNull;
                  widget.onSelectLead(lead);
                },
                decoration: const InputDecoration(labelText: 'Lead'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _task,
                decoration: const InputDecoration(labelText: 'Task'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _pickDue,
                child: Text(
                  _dueAt == null ? 'Choose due date' : _dateTimeFormat.format(_dueAt!),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: widget.selectedLead == null ||
                        _task.text.trim().isEmpty ||
                        _dueAt == null
                    ? null
                    : () async {
                        await widget.service.createReminder(
                          leadId: widget.selectedLead!.id,
                          task: _task.text.trim(),
                          dueAt: _dueAt!,
                        );
                        _task.clear();
                        setState(() => _dueAt = null);
                      },
                child: const Text('Add Reminder'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (widget.selectedLead == null)
          const SectionCard(child: Text('Select a lead to see reminders.'))
        else
          StreamBuilder<List<LeadReminder>>(
            stream: widget.service.watchReminders(widget.selectedLead!.id),
            builder: (
              BuildContext context,
              AsyncSnapshot<List<LeadReminder>> snapshot,
            ) {
              final List<LeadReminder> reminders =
                  snapshot.data ?? <LeadReminder>[];
              if (reminders.isEmpty) {
                return const SectionCard(child: Text('No reminders yet.'));
              }
              return Column(
                children: reminders
                    .map(
                      (LeadReminder reminder) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SectionCard(
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(reminder.task),
                                    const SizedBox(height: 6),
                                    Text(_dateTimeFormat.format(reminder.dueAt)),
                                  ],
                                ),
                              ),
                              FilledButton.tonal(
                                onPressed: () => widget.service.toggleReminder(
                                  leadId: widget.selectedLead!.id,
                                  reminder: reminder,
                                ),
                                child: Text(reminder.isDone ? 'Reopen' : 'Done'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
      ],
    );
  }
}

class LogsView extends StatefulWidget {
  const LogsView({
    super.key,
    required this.leads,
    required this.selectedLead,
    required this.onSelectLead,
    required this.service,
  });

  final List<Lead> leads;
  final Lead? selectedLead;
  final ValueChanged<Lead?> onSelectLead;
  final CrmService service;

  @override
  State<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<LogsView> {
  final TextEditingController _note = TextEditingController();
  String _channel = 'email';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SectionCard(
          child: Column(
            children: <Widget>[
              DropdownButtonFormField<String>(
                value: widget.selectedLead?.id,
                items: widget.leads
                    .map(
                      (Lead lead) => DropdownMenuItem<String>(
                        value: lead.id,
                        child: Text(lead.companyName),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  final Lead? lead = widget.leads
                      .where((Lead item) => item.id == value)
                      .cast<Lead?>()
                      .firstOrNull;
                  widget.onSelectLead(lead);
                },
                decoration: const InputDecoration(labelText: 'Lead'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _channel,
                items: kLogChannels
                    .map(
                      (String item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(titleCase(item)),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  if (value != null) setState(() => _channel = value);
                },
                decoration: const InputDecoration(labelText: 'Channel'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: widget.selectedLead == null || _note.text.trim().isEmpty
                    ? null
                    : () async {
                        await widget.service.addNote(
                          leadId: widget.selectedLead!.id,
                          channel: _channel,
                          note: _note.text.trim(),
                        );
                        _note.clear();
                      },
                child: const Text('Add Log'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (widget.selectedLead == null)
          const SectionCard(child: Text('Select a lead to see communication logs.'))
        else
          StreamBuilder<List<LeadLogEntry>>(
            stream: widget.service.watchNotes(widget.selectedLead!.id),
            builder: (
              BuildContext context,
              AsyncSnapshot<List<LeadLogEntry>> snapshot,
            ) {
              final List<LeadLogEntry> logs = snapshot.data ?? <LeadLogEntry>[];
              if (logs.isEmpty) {
                return const SectionCard(child: Text('No logs yet.'));
              }
              return Column(
                children: logs
                    .map(
                      (LeadLogEntry item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Chip(label: Text(item.channel.toUpperCase())),
                                  const Spacer(),
                                  Text(_dateTimeFormat.format(item.createdAt)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(item.note),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
      ],
    );
  }
}

class AiView extends StatefulWidget {
  const AiView({
    super.key,
    required this.promptController,
    required this.busy,
    required this.errorText,
    required this.reply,
    required this.onAsk,
  });

  final TextEditingController promptController;
  final bool busy;
  final String? errorText;
  final String reply;
  final VoidCallback? onAsk;

  @override
  State<AiView> createState() => _AiViewState();
}

class _AiViewState extends State<AiView> {
  @override
  void initState() {
    super.initState();
    widget.promptController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.promptController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool hasText = widget.promptController.text.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('AI Assistant', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: widget.promptController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'What would you like to ask AI?',
                  hintText: 'Summarize my pipeline and highlight leads at risk...',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.busy || widget.promptController.text.trim().isEmpty ? null : widget.onAsk,
                icon: const Icon(Icons.auto_awesome),
                label: Text(widget.busy ? 'Thinking...' : 'Ask AI'),
              ),
              if (widget.errorText != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  widget.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (widget.busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('AI is analyzing...'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <String>[
            'Summarise my pipeline and highlight top risks',
            'Draft a follow-up email for negotiation-stage leads',
            'Which lead sources convert best?',
            'What should I prioritise this week?',
          ].map(
            (String prompt) => ActionChip(
              label: Text(prompt),
              onPressed: widget.busy
                  ? null
                  : () {
                      widget.promptController.text = prompt;
                      // Optionally let user review before sending, but user complained about auto run issues
                      // So we just set the text, user can click ask. 
                    },
            ),
          ).toList(),
        ),
        if (widget.reply.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          SectionCard(child: MarkdownBody(data: widget.reply)),
        ],
      ],
    );
  }
}

class StaticPage extends StatelessWidget {
  const StaticPage({
    super.key,
    required this.title,
    required this.paragraphs,
  });

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              ...paragraphs.map(
                (String item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(item),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LeadEditorView extends StatefulWidget {
  const LeadEditorView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.errorText,
    required this.submitLabel,
    required this.initialData,
    required this.onSubmit,
  });

  final String title;
  final String subtitle;
  final bool busy;
  final String? errorText;
  final String submitLabel;
  final LeadFormData initialData;
  final Future<void> Function(LeadFormData form) onSubmit;

  @override
  State<LeadEditorView> createState() => _LeadEditorViewState();
}

class _LeadEditorViewState extends State<LeadEditorView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _company;
  late final TextEditingController _contact;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _assigned;
  late final TextEditingController _value;
  late final TextEditingController _lastTouch;
  late final TextEditingController _notes;
  late String _source;
  late String _stage;

  @override
  void initState() {
    super.initState();
    _company = TextEditingController(text: widget.initialData.companyName);
    _contact = TextEditingController(text: widget.initialData.contactName);
    _email = TextEditingController(text: widget.initialData.contactEmail);
    _phone = TextEditingController(text: widget.initialData.contactPhone);
    _assigned = TextEditingController(text: widget.initialData.assignedTo);
    _value = TextEditingController(text: widget.initialData.estimatedValue);
    _lastTouch = TextEditingController(text: widget.initialData.lastTouch);
    _notes = TextEditingController(text: widget.initialData.notes);
    _source = widget.initialData.source;
    _stage = widget.initialData.stage;
  }

  @override
  void dispose() {
    _company.dispose();
    _contact.dispose();
    _email.dispose();
    _phone.dispose();
    _assigned.dispose();
    _value.dispose();
    _lastTouch.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_lastTouch.text) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      _lastTouch.text = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {});
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.onSubmit(
      LeadFormData(
        companyName: _company.text.trim(),
        contactName: _contact.text.trim(),
        contactEmail: _email.text.trim(),
        contactPhone: _phone.text.trim(),
        source: _source,
        stage: _stage,
        estimatedValue: _value.text.trim(),
        assignedTo: _assigned.text.trim(),
        lastTouch: _lastTouch.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SectionCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(widget.subtitle),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _company,
                  decoration: const InputDecoration(labelText: 'Company Name'),
                  validator: (String? value) =>
                      (value == null || value.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contact,
                  decoration: const InputDecoration(labelText: 'Contact Name'),
                  validator: (String? value) =>
                      (value == null || value.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _source,
                  items: kSources
                      .map(
                        (String item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    if (value != null) setState(() => _source = value);
                  },
                  decoration: const InputDecoration(labelText: 'Source'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _assigned,
                  decoration: const InputDecoration(labelText: 'Assigned To'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _stage,
                  items: kStages
                      .map(
                        (String item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(titleCase(item)),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    if (value != null) setState(() => _stage = value);
                  },
                  decoration: const InputDecoration(labelText: 'Stage'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _value,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Estimated Value'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    _lastTouch.text.isEmpty ? 'Last Touch' : _lastTouch.text,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: widget.busy ? null : _submit,
                  child: Text(widget.busy ? 'Saving...' : widget.submitLabel),
                ),
                if (widget.errorText != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    widget.errorText!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A simple text-based "S" logo representing SmartCRM — no image dependency.
class BrandLogoText extends StatelessWidget {
  const BrandLogoText({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/branding/smartcmr_logo.svg',
      width: size,
      height: size,
    );
  }
}

class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      child: SectionCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
            ]
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.white,
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: isDark ? Colors.black54 : const Color(0xFFE2E8F0).withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          if (!isDark)
            const BoxShadow(
              color: Colors.white,
              blurRadius: 10,
              offset: Offset(-4, -4),
            ),
        ],
        gradient: LinearGradient(
          colors: isDark
              ? <Color>[const Color(0xFF1A1A1A), const Color(0xFF111111)]
              : <Color>[Colors.white, const Color(0xFFF8FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
