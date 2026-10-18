import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/ai.dart';
import '../services/backend.dart';
import '../services/realtime.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// AI image generation (index.html #screen-generate).
class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final _prompt = TextEditingController(text: 'A futuristic city at sunset with flying cars');
  Uint8List? _image;
  bool _busy = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      showToast('Please describe the image you want to create', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await AiService.generateImage(prompt);
      if (!mounted) return;
      setState(() => _image = bytes);
      showToast('Image generated! 🎨');
    } catch (e) {
      showToast('Failed to generate: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final bytes = _image;
    final me = AppState.instance.me;
    if (bytes == null || me == null) return;
    final items = await Backend.loadChatItems(me.id, AppState.instance.groups);
    if (!mounted) return;
    if (items.isEmpty) {
      showToast('Open a chat first to share images', error: true);
      return;
    }
    final chosen = await showModalBottomSheet<ChatItem>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Share to…', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final item in items)
              ListTile(
                leading: Avatar(
                  letter: item.isGroup ? '' : item.partner!.initial,
                  group: item.isGroup,
                ),
                title: Text(item.isGroup ? item.group!.name : item.partner!.name),
                onTap: () => Navigator.pop(ctx, item),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    try {
      final content = 'data:image/png;base64,${base64Encode(bytes)}';
      final msg = await Backend.insertMessage(
        senderId: me.id,
        receiverId: chosen.isGroup ? null : chosen.partner!.id,
        groupId: chosen.isGroup ? chosen.group!.id : null,
        content: content,
      );
      if (chosen.isGroup) Realtime.instance.sendGroupMessage(chosen.group!.id, msg);
      showToast('Image shared! 🖼️');
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => chosen.isGroup
            ? ChatScreen.group(group: chosen.group!)
            : ChatScreen.direct(partner: chosen.partner!),
      ));
    } catch (_) {
      showToast('Failed to share image', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Describe an image and HeyApp will create it for you.',
              style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 12),
          TextField(
            controller: _prompt,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(hintText: 'Describe your image...'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.bolt),
              label: Text(_busy ? 'Generating...' : 'Generate'),
            ),
          ),
          const SizedBox(height: 20),
          if (_busy)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
          else if (_image != null) ...[
            ImageBubble(bytes: _image!),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Share to chat'),
              ),
            ),
          ] else
            const EmptyState(
              icon: Icons.image_outlined,
              title: 'No image yet',
              subtitle: 'Your generated image will appear here.',
            ),
        ],
      ),
    );
  }
}
