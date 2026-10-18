import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Shared multi-select user list used by create-group and add-members.
class MemberPicker extends StatefulWidget {
  final Set<String> excludeIds;
  final ValueChanged<List<Profile>> onChanged;

  const MemberPicker({super.key, this.excludeIds = const {}, required this.onChanged});

  @override
  State<MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<MemberPicker> {
  final _search = TextEditingController();
  final Map<String, Profile> _selected = {};
  List<Profile> _candidates = [];

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String term) async {
    final me = AppState.instance.me;
    if (me == null) return;
    try {
      // An empty term lists the first users, like the candidate list in index.html.
      final users = await Backend.searchUsers(me.id, term.trim());
      if (!mounted) return;
      setState(() => _candidates = users.where((u) => !widget.excludeIds.contains(u.id)).toList());
    } catch (_) {}
  }

  void _toggle(Profile p) {
    setState(() {
      if (_selected.containsKey(p.id)) {
        _selected.remove(p.id);
      } else {
        _selected[p.id] = p;
      }
    });
    widget.onChanged(_selected.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            controller: _search,
            autocorrect: false,
            onChanged: (v) => _load(v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search people to add...'),
          ),
        ),
        if (_selected.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final p in _selected.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                    child: InputChip(label: Text(p.name), onDeleted: () => _toggle(p)),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _candidates.isEmpty
              ? const EmptyState(icon: Icons.person_search, title: 'No people found', subtitle: 'Try another name.')
              : ListView.builder(
                  itemCount: _candidates.length,
                  itemBuilder: (context, i) {
                    final u = _candidates[i];
                    final checked = _selected.containsKey(u.id);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      leading: Avatar(letter: u.initial),
                      title: Text(u.name),
                      subtitle: Text('@${u.username}', style: const TextStyle(color: AppColors.textDim)),
                      trailing: Icon(
                        checked ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: checked ? AppColors.accent : AppColors.textFaint,
                      ),
                      onTap: () => _toggle(u),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Create group: pick members, then name it (index.html #screen-group-create / #screen-group-name).
class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  List<Profile> _picked = [];
  bool _nameStep = false;
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _next() {
    if (_picked.isEmpty) {
      showToast('Add at least one person to the group', error: true);
      return;
    }
    setState(() => _nameStep = true);
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final me = AppState.instance.me;
    if (me == null) return;
    if (name.isEmpty) return setState(() => _error = 'Please give your group a name');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final group = await Backend.createGroup(
        name: name,
        myId: me.id,
        memberIds: _picked.map((p) => p.id).toList(),
      );
      showToast('Group "$name" created 🎉');
      await AppState.instance.refreshGroups();
      if (!mounted) return;
      // Open the new group chat, replacing this screen (same as openGroupChat in index.html).
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen.group(group: group),
      ));
    } catch (e) {
      final msg = e.toString();
      final friendly = msg.contains('row-level security')
          ? 'Blocked by Row Level Security — add an insert/select policy for groups and group_members.'
          : 'Failed to create group. $msg';
      setState(() => _error = friendly);
      showToast(friendly, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_nameStep) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Name your group'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _nameStep = false)),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${_picked.length} member${_picked.length > 1 ? 's' : ''} selected',
                style: const TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 40,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _create(),
              decoration: const InputDecoration(hintText: 'e.g. Weekend Squad'),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(onPressed: _busy ? null : _create, child: Text(_busy ? 'Creating…' : 'Create group')),
            ),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: [TextButton(onPressed: _next, child: const Text('Next'))],
      ),
      body: MemberPicker(onChanged: (list) => setState(() => _picked = list)),
    );
  }
}

/// Group details: members, add people, leave (index.html #screen-group-info).
class GroupInfoScreen extends StatefulWidget {
  final Group group;
  const GroupInfoScreen({super.key, required this.group});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  Group get _group {
    final match = AppState.instance.groups.where((g) => g.id == widget.group.id);
    return match.isEmpty ? widget.group : match.first;
  }

  Future<void> _addMembers() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddMembersScreen(group: _group)));
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Are you sure you want to leave "${_group.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final me = AppState.instance.me;
    if (me == null) return;
    try {
      await Backend.leaveGroup(_group.id, me.id);
      showToast('You left the group');
      await AppState.instance.refreshGroups();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      showToast('Failed to leave group', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _group;
    final count = g.members.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Avatar(letter: '', group: true, size: 84),
              const SizedBox(height: 14),
              Text(g.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Group • $count member${count == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textFaint)),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: const Text('Add people'),
            onTap: _addMembers,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text('$count MEMBER${count == 1 ? '' : 'S'}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
          ),
          for (final m in g.members)
            ListTile(
              leading: Avatar(letter: m.initial, online: m.isOnline),
              title: Text(m.name),
              subtitle: Text('@${m.username}', style: const TextStyle(color: AppColors.textDim)),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text('Leave group', style: TextStyle(color: AppColors.danger)),
            onTap: _leave,
          ),
        ],
      ),
    );
  }
}

/// Add members to an existing group (index.html #screen-group-add-members).
class AddMembersScreen extends StatefulWidget {
  final Group group;
  const AddMembersScreen({super.key, required this.group});

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  List<Profile> _picked = [];

  Future<void> _confirm() async {
    if (_picked.isEmpty) {
      showToast('Select at least one person to add', error: true);
      return;
    }
    try {
      await Backend.addMembers(widget.group.id, _picked.map((p) => p.id).toList());
      await AppState.instance.refreshGroups();
      showToast('Members added ✓');
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      showToast('Failed to add members', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.group.members.map((m) => m.id).toSet();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add people'),
        actions: [TextButton(onPressed: _confirm, child: const Text('Add'))],
      ),
      body: MemberPicker(
        excludeIds: existing,
        onChanged: (list) => setState(() => _picked = list),
      ),
    );
  }
}
