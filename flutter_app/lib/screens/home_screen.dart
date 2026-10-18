import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/backend.dart';
import '../services/realtime.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth_screens.dart';
import 'chat_screen.dart';
import 'generate_screen.dart';
import 'group_screens.dart';

/// Bottom-nav shell: Chats / Search / Generate / Settings (index.html bottom nav).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const ChatsTab(),
      const SearchTab(),
      const GenerateScreen(),
      const SettingsTab(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt), label: 'Generate'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Chats

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  List<ChatItem> _items = [];
  bool _loading = true;
  StreamSubscription<Message>? _dmSub;
  StreamSubscription<Message>? _groupSub;
  final AppState _app = AppState.instance;

  @override
  void initState() {
    super.initState();
    _app.addListener(_refresh);
    _dmSub = Realtime.instance.directMessages.listen((_) => _refresh());
    _groupSub = Realtime.instance.groupMessages.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _app.removeListener(_refresh);
    _dmSub?.cancel();
    _groupSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final me = _app.me;
    if (me == null) return;
    try {
      final items = await Backend.loadChatItems(me.id, _app.groups);
      if (mounted) setState(() => _items = items);
    } catch (_) {
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  String _preview(ChatItem item) {
    final last = item.lastMessage;
    if (item.isGroup) {
      if (last == null) return 'No messages yet';
      final me = _app.me;
      String sender = 'Someone';
      if (last.senderId == me?.id) {
        sender = 'You';
      } else {
        for (final m in item.group!.members) {
          if (m.id == last.senderId) sender = m.name;
        }
      }
      return '$sender: ${last.isImage ? '📷 Photo' : last.content}';
    }
    final body = last == null ? '' : (last.isImage ? '📷 Photo' : last.content);
    return '@${item.partner!.username} • $body';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HeyApp', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
        actions: [
          IconButton(
            tooltip: 'New group',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GroupCreateScreen()),
            ).then((_) => _app.refreshGroups()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _app.refreshGroups,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    EmptyState(
                      icon: Icons.chat_bubble_outline,
                      title: 'No Messages Yet',
                      subtitle: 'Search for friends or start a group to begin chatting!',
                    ),
                  ])
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      final name = item.isGroup ? item.group!.name : item.partner!.name;
                      final last = item.lastMessage;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        leading: Avatar(
                          letter: item.isGroup ? '' : item.partner!.initial,
                          group: item.isGroup,
                          online: !item.isGroup && item.partner!.isOnline,
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(_preview(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (last != null)
                              Text(formatRelative(last.createdAt),
                                  style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                            if (item.unread > 0)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('${item.unread}',
                                    style: const TextStyle(
                                        color: AppColors.onAccent, fontSize: 11, fontWeight: FontWeight.w800)),
                              ),
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => item.isGroup
                              ? ChatScreen.group(group: item.group!)
                              : ChatScreen.direct(partner: item.partner!),
                        )).then((_) => _refresh()),
                      );
                    },
                  ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Search

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Profile> _results = [];
  final Set<String> _starting = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String raw) async {
    final term = raw.trim();
    final me = AppState.instance.me;
    if (me == null || term.length < 2) {
      setState(() => _results = []);
      return;
    }
    try {
      final byEmail = term.contains('@') && emailPattern.hasMatch(term);
      final users = await Backend.searchUsers(me.id, term, byEmail: byEmail);
      if (mounted) setState(() => _results = users);
    } catch (_) {}
  }

  Future<void> _startChat(Profile user) async {
    final me = AppState.instance.me;
    if (me == null || _starting.contains(user.id)) return;
    setState(() => _starting.add(user.id));
    try {
      await Backend.ensureConversation(me.id, user);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen.direct(partner: user)));
    } catch (_) {
      showToast('Failed to start chat', error: true);
    } finally {
      if (mounted) setState(() => _starting.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find people')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              autocorrect: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search username or email...',
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final u = _results[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Avatar(letter: u.initial, online: u.isOnline),
                  title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('@${u.username}', style: const TextStyle(color: AppColors.textDim)),
                  trailing: FilledButton.tonal(
                    onPressed: _starting.contains(u.id) ? null : () => _startChat(u),
                    child: const Text('Message'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Settings

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final app = AppState.instance;
        final me = app.me;
        final langName = translateLanguages.firstWhere(
          (l) => l[0] == app.translateLang,
          orElse: () => const ['', 'Off'],
        )[1];
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            children: [
              if (me != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Avatar(letter: me.initial, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(me.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text('@${me.username}', style: const TextStyle(color: AppColors.textDim)),
                      ]),
                    ),
                  ]),
                ),
              _section('Account', [
                _row(Icons.person_outline, 'Edit profile', 'Change your display name',
                    () => _editName(context)),
              ]),
              _section('Preferences', [
                _row(Icons.palette_outlined, 'Theme',
                    app.themeMode == ThemeMode.light ? 'Light' : 'Dark', () => _pickTheme(context)),
                _row(Icons.translate, 'Translate messages', langName, () => _pickLanguage(context)),
              ]),
              _section('About', [
                _row(Icons.description_outlined, 'Terms & Conditions', null, () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermsScreen()));
                }),
                _row(Icons.info_outline, 'Version', AppInfo.version, () => showToast('Version ${AppInfo.version}')),
              ]),
              _section('', [
                _row(Icons.logout, 'Log out', null, () => _confirmLogout(context), danger: true),
              ]),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(title.toUpperCase(),
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
          ),
        ...rows,
      ],
    );
  }

  Widget _row(IconData icon, String label, String? sub, VoidCallback onTap, {bool danger = false}) {
    final color = danger ? AppColors.danger : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      subtitle: sub == null ? null : Text(sub),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textFaint),
      onTap: onTap,
    );
  }

  Future<void> _editName(BuildContext context) async {
    final me = AppState.instance.me;
    if (me == null) return;
    final controller = TextEditingController(text: me.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit profile'),
        content: TextField(
          controller: controller,
          maxLength: 40,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Your name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) {
      if (newName != null) showToast('Name cannot be empty', error: true);
      return;
    }
    try {
      final updated = await Backend.updateName(me.id, newName);
      AppState.instance.setMe(updated);
      showToast('Name updated ✓');
    } catch (_) {
      showToast('Failed to update — please try again', error: true);
    }
  }

  Future<void> _pickTheme(BuildContext context) async {
    final app = AppState.instance;
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose Theme'),
        children: [
          for (final mode in [ThemeMode.light, ThemeMode.dark])
            RadioListTile<ThemeMode>(
              value: mode,
              groupValue: app.themeMode,
              title: Text(mode == ThemeMode.light ? 'Light' : 'Dark'),
              subtitle: Text(mode == ThemeMode.light ? 'Bright and clean' : 'Easy on the eyes'),
              onChanged: (v) {
                if (v != null) app.setThemeMode(v);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final app = AppState.instance;
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Translate messages to'),
        children: [
          for (final l in translateLanguages)
            RadioListTile<String>(
              value: l[0],
              groupValue: app.translateLang,
              title: Text(l[1]),
              onChanged: (v) {
                app.setTranslateLang(v ?? '');
                showToast(v == null || v.isEmpty ? 'Translation turned off' : 'Translation enabled ✓');
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppState.instance.endSession();
    showToast('Logged out successfully');
    if (context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }
}

class AppInfo {
  static const version = '1.1.0';
}
