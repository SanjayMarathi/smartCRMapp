import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

const String kAiBaseUrl = 'https://crmlead-crmllm.hf.space';

String normalizeEmail(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.contains('@')) return trimmed;
  return '$trimmed@smartcrm.app';
}

String friendlyAuthError(String message) {
  if (message.contains('invalid-credential') ||
      message.contains('wrong-password') ||
      message.contains('user-not-found')) {
    return 'Incorrect email or password.';
  }
  if (message.contains('email-already-in-use')) {
    return 'An account with this email already exists.';
  }
  if (message.contains('weak-password')) {
    return 'Password must be at least 6 characters.';
  }
  if (message.contains('invalid-email')) {
    return 'Please enter a valid email address.';
  }
  if (message.contains('too-many-requests')) {
    return 'Too many attempts. Wait a moment and try again.';
  }
  return message.replaceFirst('Exception: ', '');
}

String displayNameForUser(fb_auth.User user) {
  return user.displayName ?? user.email?.split('@').first ?? 'User';
}

class FirebaseEnvConfig {
  static const String projectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'smartcrm-dd52b');
  static const String messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '194743461478');
  static const String storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: 'smartcrm-dd52b.firebasestorage.app');
  static const String androidApiKey =
      String.fromEnvironment('FIREBASE_ANDROID_API_KEY', defaultValue: 'AIzaSyAnCXax2VpJsVOeGe284Y7W1X09q-0Y0RQ');
  static const String androidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID', defaultValue: '1:194743461478:android:6299a32a335ef71331afa7'); // Placeholder Android ID
  static const String iosApiKey =
      String.fromEnvironment('FIREBASE_IOS_API_KEY', defaultValue: 'AIzaSyAnCXax2VpJsVOeGe284Y7W1X09q-0Y0RQ');
  static const String iosAppId =
      String.fromEnvironment('FIREBASE_IOS_APP_ID', defaultValue: '1:194743461478:ios:6299a32a335ef71331afa7'); // Placeholder iOS ID
  static const String iosBundleId =
      String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID', defaultValue: 'com.smartcmr.app');

  static bool get isConfiguredForCurrentPlatform {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      return projectId.isNotEmpty &&
          messagingSenderId.isNotEmpty &&
          storageBucket.isNotEmpty &&
          androidApiKey.isNotEmpty &&
          androidAppId.isNotEmpty;
    }
    if (Platform.isIOS) {
      return projectId.isNotEmpty &&
          messagingSenderId.isNotEmpty &&
          storageBucket.isNotEmpty &&
          iosApiKey.isNotEmpty &&
          iosAppId.isNotEmpty &&
          iosBundleId.isNotEmpty;
    }
    return false;
  }

  static FirebaseOptions get currentPlatform {
    if (Platform.isAndroid) {
      return FirebaseOptions(
        apiKey: androidApiKey,
        appId: androidAppId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        storageBucket: storageBucket,
      );
    }
    if (Platform.isIOS) {
      return FirebaseOptions(
        apiKey: iosApiKey,
        appId: iosAppId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        storageBucket: storageBucket,
        iosBundleId: iosBundleId,
      );
    }
    throw UnsupportedError('SmartCRM targets Android and iOS only.');
  }
}

class FirebaseAuthService {
  FirebaseAuthService._();

  static final FirebaseAuthService instance = FirebaseAuthService._();

  fb_auth.FirebaseAuth get _auth => fb_auth.FirebaseAuth.instance;

  Stream<fb_auth.User?> get authChanges => _auth.authStateChanges();

  Future<void> signIn({
    required String emailOrUsername,
    required String password,
  }) async {
    final String email = normalizeEmail(emailOrUsername);
    if (email.isEmpty) throw Exception('Email is required.');
    if (password.isEmpty) throw Exception('Password is required.');
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String username,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final String resolvedEmail =
        email.trim().isEmpty ? normalizeEmail(username) : email.trim();
    if (resolvedEmail.isEmpty || password.isEmpty) {
      throw Exception('Email and password are required.');
    }
    if (password != confirmPassword) {
      throw Exception('Passwords do not match.');
    }

    final fb_auth.UserCredential credential =
        await _auth.createUserWithEmailAndPassword(
      email: resolvedEmail,
      password: password,
    );
    if (username.trim().isNotEmpty) {
      await credential.user?.updateDisplayName(username.trim());
    }
  }

  Future<void> signOut() => _auth.signOut();
}

class CrmService {
  CrmService._();

  static final CrmService instance = CrmService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  fb_auth.FirebaseAuth get _auth => fb_auth.FirebaseAuth.instance;

  Stream<List<Lead>> watchLeads() {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return Stream<List<Lead>>.value(<Lead>[]);

    return _db
        .collection('leads')
        .where('owner_uid', isEqualTo: uid)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      final List<Lead> items = snapshot.docs.map(Lead.fromDoc).toList();
      items.sort((Lead a, Lead b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  Future<void> createLead(LeadFormData form) async {
    final fb_auth.User? user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated.');
    await _db.collection('leads').add(<String, dynamic>{
      ..._leadPayload(form, user),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateLead(String leadId, LeadFormData form) async {
    final fb_auth.User? user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated.');
    await _db.collection('leads').doc(leadId).update(_leadPayload(form, user));
  }

  Stream<List<LeadLogEntry>> watchNotes(String leadId) {
    return _db
        .collection('leads')
        .doc(leadId)
        .collection('notes')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      final List<LeadLogEntry> items =
          snapshot.docs.map(LeadLogEntry.fromDoc).toList();
      items.sort((LeadLogEntry a, LeadLogEntry b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  Future<void> addNote({
    required String leadId,
    required String channel,
    required String note,
  }) async {
    if (_auth.currentUser == null) throw Exception('Not authenticated.');
    await _db.collection('leads').doc(leadId).collection('notes').add(
      <String, dynamic>{
        'channel': channel,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Stream<List<LeadReminder>> watchReminders(String leadId) {
    return _db
        .collection('leads')
        .doc(leadId)
        .collection('reminders')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      final List<LeadReminder> items =
          snapshot.docs.map(LeadReminder.fromDoc).toList();
      items.sort((LeadReminder a, LeadReminder b) => a.dueAt.compareTo(b.dueAt));
      return items;
    });
  }

  Future<void> createReminder({
    required String leadId,
    required String task,
    required DateTime dueAt,
  }) async {
    if (_auth.currentUser == null) throw Exception('Not authenticated.');
    await _db.collection('leads').doc(leadId).collection('reminders').add(
      <String, dynamic>{
        'task': task,
        'due_at': dueAt.toIso8601String(),
        'is_done': false,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> toggleReminder({
    required String leadId,
    required LeadReminder reminder,
  }) {
    return _db
        .collection('leads')
        .doc(leadId)
        .collection('reminders')
        .doc(reminder.id)
        .update(<String, dynamic>{'is_done': !reminder.isDone});
  }

  Future<String> askAi({
    required String prompt,
    required List<Lead> leads,
  }) async {
    final StringBuffer leadContext = StringBuffer();
    if (leads.isNotEmpty) {
      leadContext.writeln('\n\nCurrent pipeline summary (${leads.length} leads):');
      for (final Lead lead in leads) {
        leadContext.writeln(
          '- ${lead.companyName} | Stage: ${lead.stage} | Value: ${lead.estimatedValue.toStringAsFixed(0)} | Source: ${lead.source}',
        );
      }
    }

    final http.Response response = await http.post(
      Uri.parse('$kAiBaseUrl/generate'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(
        <String, dynamic>{
          'user_prompt': '$prompt${leadContext.toString()}',
          'system_prompt':
              'You are a highly capable AI assistant built for a CRM. Provide all responses in strictly well-formatted Markdown. DO NOT use markdown tables under any circumstances. Present data rows logically using bullet points or numbered lists ONLY. Ensure proper spacing, bold headings, and easily readable indentation.',
          'max_new_tokens': 512,
          'temperature': 0.2,
          'top_p': 0.95,
          'repetition_penalty': 1.05,
        },
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AI request failed (${response.statusCode})');
    }

    final dynamic payload = jsonDecode(response.body);
    return (payload['response'] ??
            payload['reply'] ??
            payload['generated_text'] ??
            payload['output'] ??
            payload['choices']?[0]?['message']?['content'] ??
            '')
        .toString();
  }

  Map<String, dynamic> _leadPayload(LeadFormData form, fb_auth.User user) {
    final double value = double.tryParse(form.estimatedValue) ?? 0;
    return <String, dynamic>{
      'company_name': form.companyName,
      'company': form.companyName,
      'contact_name': form.contactName,
      'name': form.contactName,
      'contact_email': form.contactEmail,
      'email': form.contactEmail,
      'contact_phone': form.contactPhone,
      'phone': form.contactPhone,
      'source': form.source,
      'stage': form.stage,
      'status': form.stage,
      'estimated_value': value,
      'value': value,
      'assigned_to': form.assignedTo,
      'last_touch': form.lastTouch,
      'notes': form.notes,
      'owner_uid': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
