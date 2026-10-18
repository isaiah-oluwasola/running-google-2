import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services/auth.dart';
import 'services/backend.dart';
import 'services/calls.dart';
import 'services/realtime.dart';

/// App-wide state: the signed-in profile, groups, theme and translation preference.
/// Preference keys match index.html's localStorage keys.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  Profile? me;
  List<Group> groups = [];
  ThemeMode themeMode = ThemeMode.dark;
  String translateLang = '';

  SharedPreferences? _prefs;

  Future<void> loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final theme = _prefs!.getString('sayhi_theme');
    themeMode = theme == 'light' ? ThemeMode.light : ThemeMode.dark;
    translateLang = _prefs!.getString('sayhi_translate_lang') ?? '';
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _prefs?.setString('sayhi_theme', mode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  void setTranslateLang(String code) {
    translateLang = code;
    _prefs?.setString('sayhi_translate_lang', code);
    notifyListeners();
  }

  void setMe(Profile profile) {
    me = profile;
    notifyListeners();
  }

  /// Runs after a profile is loaded or created: online status, realtime, call listener, groups.
  Future<void> startSession(Profile profile) async {
    me = profile;
    try {
      await Backend.setOnline(profile.id, true);
    } catch (_) {}
    Realtime.instance.startDirect(profile.id);
    CallService.instance.listen(profile.id, profile.name);
    await refreshGroups();
    notifyListeners();
  }

  Future<void> refreshGroups() async {
    final myId = me?.id;
    if (myId == null) return;
    try {
      groups = await Backend.loadMyGroups(myId);
    } catch (_) {
      groups = [];
    }
    Realtime.instance.syncGroups(groups);
    notifyListeners();
  }

  Future<void> endSession() async {
    final myId = me?.id;
    await CallService.instance.endCall();
    CallService.instance.stopListening();
    Realtime.instance.stopAll();
    if (myId != null) {
      try {
        await Backend.setOnline(myId, false);
      } catch (_) {}
    }
    await AuthService.signOut();
    me = null;
    groups = [];
    notifyListeners();
  }
}
