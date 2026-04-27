import 'package:cloud_firestore/cloud_firestore.dart';

const List<String> kStages = <String>[
  'new',
  'qualified',
  'proposal',
  'negotiation',
  'won',
  'lost',
];

const List<String> kSources = <String>[
  'Website',
  'Referral',
  'Cold Outreach',
  'LinkedIn',
  'Event',
  'Other',
];

const List<String> kLogChannels = <String>[
  'email',
  'call',
  'meeting',
  'chat',
];

DateTime timestampToDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

class Lead {
  const Lead({
    required this.id,
    required this.companyName,
    required this.contactName,
    required this.contactEmail,
    required this.contactPhone,
    required this.source,
    required this.stage,
    required this.estimatedValue,
    required this.assignedTo,
    required this.lastTouch,
    required this.notes,
    required this.ownerUid,
    required this.createdAt,
  });

  factory Lead.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return Lead(
      id: doc.id,
      companyName: (data['company_name'] ?? data['company'] ?? '').toString(),
      contactName: (data['contact_name'] ?? data['name'] ?? '').toString(),
      contactEmail: (data['contact_email'] ?? data['email'] ?? '').toString(),
      contactPhone: (data['contact_phone'] ?? data['phone'] ?? '').toString(),
      source: (data['source'] ?? 'Unknown').toString(),
      stage: (data['stage'] ?? data['status'] ?? 'new').toString(),
      estimatedValue: (data['estimated_value'] ?? data['value'] ?? 0).toDouble(),
      assignedTo: (data['assigned_to'] ?? '').toString(),
      lastTouch: (data['last_touch'] ?? '').toString(),
      notes: (data['notes'] ?? '').toString(),
      ownerUid: (data['owner_uid'] ?? '').toString(),
      createdAt: timestampToDate(data['createdAt']),
    );
  }

  final String id;
  final String companyName;
  final String contactName;
  final String contactEmail;
  final String contactPhone;
  final String source;
  final String stage;
  final double estimatedValue;
  final String assignedTo;
  final String lastTouch;
  final String notes;
  final String ownerUid;
  final DateTime createdAt;
}

class LeadLogEntry {
  const LeadLogEntry({
    required this.id,
    required this.channel,
    required this.note,
    required this.createdAt,
  });

  factory LeadLogEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return LeadLogEntry(
      id: doc.id,
      channel: (data['channel'] ?? 'note').toString(),
      note: (data['note'] ?? '').toString(),
      createdAt: timestampToDate(data['created_at'] ?? data['createdAt']),
    );
  }

  final String id;
  final String channel;
  final String note;
  final DateTime createdAt;
}

class LeadReminder {
  const LeadReminder({
    required this.id,
    required this.task,
    required this.dueAt,
    required this.isDone,
  });

  factory LeadReminder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    return LeadReminder(
      id: doc.id,
      task: (data['task'] ?? '').toString(),
      dueAt: timestampToDate(data['due_at']),
      isDone: data['is_done'] == true,
    );
  }

  final String id;
  final String task;
  final DateTime dueAt;
  final bool isDone;
}

class LeadFormData {
  const LeadFormData({
    this.companyName = '',
    this.contactName = '',
    this.contactEmail = '',
    this.contactPhone = '',
    this.source = 'Website',
    this.stage = 'new',
    this.estimatedValue = '',
    this.assignedTo = '',
    this.lastTouch = '',
    this.notes = '',
  });

  factory LeadFormData.fromLead(Lead lead) {
    return LeadFormData(
      companyName: lead.companyName,
      contactName: lead.contactName,
      contactEmail: lead.contactEmail,
      contactPhone: lead.contactPhone,
      source: lead.source,
      stage: lead.stage,
      estimatedValue: lead.estimatedValue.toStringAsFixed(0),
      assignedTo: lead.assignedTo,
      lastTouch: lead.lastTouch,
      notes: lead.notes,
    );
  }

  final String companyName;
  final String contactName;
  final String contactEmail;
  final String contactPhone;
  final String source;
  final String stage;
  final String estimatedValue;
  final String assignedTo;
  final String lastTouch;
  final String notes;

  LeadFormData copyWith({
    String? companyName,
    String? contactName,
    String? contactEmail,
    String? contactPhone,
    String? source,
    String? stage,
    String? estimatedValue,
    String? assignedTo,
    String? lastTouch,
    String? notes,
  }) {
    return LeadFormData(
      companyName: companyName ?? this.companyName,
      contactName: contactName ?? this.contactName,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      source: source ?? this.source,
      stage: stage ?? this.stage,
      estimatedValue: estimatedValue ?? this.estimatedValue,
      assignedTo: assignedTo ?? this.assignedTo,
      lastTouch: lastTouch ?? this.lastTouch,
      notes: notes ?? this.notes,
    );
  }
}

class PipelineStats {
  const PipelineStats({
    required this.totalValue,
    required this.wonValue,
    required this.averageDeal,
    required this.wonCount,
    required this.lostCount,
    required this.conversionRate,
    required this.stageCounts,
    required this.sourceBreakdown,
  });

  factory PipelineStats.fromLeads(List<Lead> leads) {
    final Map<String, int> stages = <String, int>{
      for (final String stage in kStages) stage: 0,
    };
    final Map<String, int> sources = <String, int>{};
    double total = 0;
    double won = 0;

    for (final Lead lead in leads) {
      stages[lead.stage] = (stages[lead.stage] ?? 0) + 1;
      sources[lead.source] = (sources[lead.source] ?? 0) + 1;
      total += lead.estimatedValue;
      if (lead.stage == 'won') {
        won += lead.estimatedValue;
      }
    }

    final int wonCount = stages['won'] ?? 0;
    final int lostCount = stages['lost'] ?? 0;
    final double averageDeal = leads.isEmpty ? 0 : total / leads.length;
    final int conversionRate = leads.isEmpty ? 0 : ((wonCount / leads.length) * 100).round();

    final List<MapEntry<String, int>> sourceEntries = sources.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));

    return PipelineStats(
      totalValue: total,
      wonValue: won,
      averageDeal: averageDeal,
      wonCount: wonCount,
      lostCount: lostCount,
      conversionRate: conversionRate,
      stageCounts: stages,
      sourceBreakdown: Map<String, int>.fromEntries(sourceEntries),
    );
  }

  final double totalValue;
  final double wonValue;
  final double averageDeal;
  final int wonCount;
  final int lostCount;
  final int conversionRate;
  final Map<String, int> stageCounts;
  final Map<String, int> sourceBreakdown;
}
