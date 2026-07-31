import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_session.dart';

class OnboardingService {
  static const _version = 2;

  Future<String> _userKey() async {
    final onlineId = Supabase.instance.client.auth.currentUser?.id.trim() ?? '';
    final cachedId = (await LocalSession().cachedUserId())?.trim() ?? '';
    final id = onlineId.isNotEmpty ? onlineId : cachedId;
    return 'zumac_onboarding_v$_version:${id.isEmpty ? 'device' : id}';
  }

  Future<bool> shouldShow() async {
    final preferences = await SharedPreferences.getInstance();
    return !(preferences.getBool(await _userKey()) ?? false);
  }

  Future<void> markSeen() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(await _userKey(), true);
  }
}
